import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item.dart';
import '../models/reservation.dart';
import 'database_service.dart';

class CloudSyncService {
  static final CloudSyncService instance = CloudSyncService._();

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');
  final Random _random = Random.secure();
  final DatabaseService _database = DatabaseService();

  String? _tenantId;
  String? _deviceId;
  Timer? _retryTimer;
  bool _flushing = false;

  CloudSyncService._();

  Future<void> configure({
    required String tenantId,
    required String deviceId,
    required bool botMode,
  }) async {
    if (!botMode) {
      clear();
      return;
    }
    await _database.setTenant(tenantId);
    _tenantId = tenantId;
    _deviceId = deviceId;
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => flushPendingEvents(),
    );
    await _restoreIfEmpty();
    unawaited(_publishExistingData());
    unawaited(publishBotSettings());
    unawaited(flushPendingEvents());
  }

  void clear() {
    _tenantId = null;
    _deviceId = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _database.clearTenant();
  }

  Future<void> publishReservationCreated({
    required Reservation reservation,
    required Item item,
  }) async {
    await _publish(
      type: 'created',
      reservationId: _reservationId(reservation),
      itemId: item.id.toString(),
      itemName: item.name,
      nickname: reservation.nickname,
      roomName: reservation.roomName,
      businessDate: DateFormat('yyyy-MM-dd').format(reservation.createdAt),
    );
  }

  Future<void> publishReservationCancelled({
    required Reservation reservation,
  }) async {
    await _publish(
      type: 'cancelled',
      reservationId: _reservationId(reservation),
      itemId: reservation.itemId.toString(),
      nickname: reservation.nickname,
      roomName: reservation.roomName,
      businessDate: DateFormat('yyyy-MM-dd').format(reservation.createdAt),
    );
  }

  Future<void> publishReset(
      {required Item item, required DateTime date}) async {
    await _publish(
      type: 'reset',
      reservationId: _id('reset'),
      itemId: item.id.toString(),
      itemName: item.name,
      businessDate: DateFormat('yyyy-MM-dd').format(date),
    );
  }

  Future<void> publishItem(Item item) async {
    final tenantId = _tenantId;
    if (tenantId == null || item.id == null) return;
    try {
      await _functions.httpsCallable('upsertItem').call({
        'tenantId': tenantId,
        'itemId': item.id.toString(),
        'name': item.name,
        'maxCapacity': item.maxCapacity,
        'template': item.template,
        'sourceDeviceId': _deviceId ?? '',
      });
    } catch (error, stack) {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: 'item cloud sync failed',
        fatal: false,
      );
    }
  }

  Future<void> deleteItem(int itemId) async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    try {
      await _functions.httpsCallable('deleteItem').call({
        'tenantId': tenantId,
        'itemId': itemId.toString(),
        'sourceDeviceId': _deviceId ?? '',
      });
    } catch (error, stack) {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: 'item cloud delete failed',
        fatal: false,
      );
    }
  }

  Future<void> _publishExistingData() async {
    final activeTenantId = _tenantId;
    if (activeTenantId == null) return;

    final items = await _database.getItems();
    if (_tenantId != activeTenantId) return;

    for (final item in items) {
      if (_tenantId != activeTenantId) return;
      await publishItem(item);
    }
    final itemsById = {
      for (final item in items)
        if (item.id != null) item.id!: item,
    };
    final reservations = await _database.getReservations();
    if (_tenantId != activeTenantId) return;

    for (final reservation in reservations) {
      if (_tenantId != activeTenantId) return;
      final item = itemsById[reservation.itemId];
      if (item == null) continue;
      await _publish(
        eventId: 'migration-${_deviceId ?? 'local'}-${reservation.id}',
        type: 'created',
        reservationId: _reservationId(reservation),
        itemId: item.id.toString(),
        itemName: item.name,
        nickname: reservation.nickname,
        roomName: reservation.roomName,
        businessDate: DateFormat('yyyy-MM-dd').format(reservation.createdAt),
      );
    }
  }

  Future<void> _restoreIfEmpty() async {
    final tenantId = _tenantId;
    final deviceId = _deviceId;
    if (tenantId == null || deviceId == null) return;

    final hasItems = await _database.hasLocalItems();
    if (_tenantId != tenantId) return;
    if (hasItems) return;

    try {
      final result = await _functions.httpsCallable('getBotSnapshot').call({
        'tenantId': tenantId,
        'deviceId': deviceId,
      });
      if (_tenantId != tenantId) return;

      final data = Map<String, dynamic>.from(result.data as Map);
      final items = (data['items'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final reservations = (data['reservations'] as List? ?? const [])
          .map((reservation) => Map<String, dynamic>.from(reservation as Map))
          .toList();
      final rooms = (data['rooms'] as List? ?? const [])
          .map((room) => Map<String, dynamic>.from(room as Map))
          .toList();
      await _restorePreferences(
        Map<String, dynamic>.from(data['settings'] as Map? ?? const {}),
      );
      if (_tenantId != tenantId) return;

      await _database.restoreBotSnapshot(
        items: items,
        reservations: reservations,
        rooms: rooms,
      );
    } catch (error, stack) {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: 'bot snapshot restore failed',
        fatal: false,
      );
    }
  }

  Future<void> publishBotSettings() async {
    final tenantId = _tenantId;
    final deviceId = _deviceId;
    if (tenantId == null || deviceId == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    if (_tenantId != tenantId) return;

    final rooms = await _database.getRooms();
    if (_tenantId != tenantId) return;

    try {
      await _functions.httpsCallable('updateBotSettings').call({
        'tenantId': tenantId,
        'deviceId': deviceId,
        'commands': {
          'reserve': prefs.getString('cmd_reserve') ?? '예약',
          'cancel': prefs.getString('cmd_cancel') ?? '예약취소',
          'status': prefs.getString('cmd_status') ?? '조회',
          'reset': prefs.getString('cmd_reset') ?? '초기화',
          'max': prefs.getString('cmd_max') ?? '세팅최대',
          'template': prefs.getString('cmd_template') ?? '텍스트변경',
          'total': prefs.getString('cmd_total') ?? '전체조회',
        },
        'totalTemplate':
            prefs.getString('total_template') ?? '📊 전체 예약 현황 📊\n{전체현황}',
        'resetHour': prefs.getInt('reset_hour') ?? 0,
        'resetMinute': prefs.getInt('reset_minute') ?? 0,
        'rooms': rooms
            .map((room) => {
                  'name': room.name,
                  'type': room.type.name,
                })
            .toList(),
      });
    } catch (error, stack) {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: 'bot settings cloud sync failed',
        fatal: false,
      );
    }
  }

  Future<void> _restorePreferences(Map<String, dynamic> settings) async {
    if (settings.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final commands =
        Map<String, dynamic>.from(settings['commands'] as Map? ?? const {});
    final stringSettings = {
      'cmd_reserve': commands['reserve'],
      'cmd_cancel': commands['cancel'],
      'cmd_status': commands['status'],
      'cmd_reset': commands['reset'],
      'cmd_max': commands['max'],
      'cmd_template': commands['template'],
      'cmd_total': commands['total'],
      'total_template': settings['totalTemplate'],
    };
    for (final entry in stringSettings.entries) {
      final value = entry.value?.toString();
      if (value != null && value.isNotEmpty) {
        await prefs.setString(entry.key, value);
      }
    }
    final resetHour = settings['resetHour'];
    final resetMinute = settings['resetMinute'];
    if (resetHour is num) await prefs.setInt('reset_hour', resetHour.toInt());
    if (resetMinute is num) {
      await prefs.setInt('reset_minute', resetMinute.toInt());
    }
  }

  Future<void> _publish({
    String? eventId,
    required String type,
    required String reservationId,
    required String itemId,
    required String businessDate,
    String itemName = '',
    String nickname = '',
    String roomName = '',
  }) async {
    final payload = {
      'tenantId': _tenantId,
      'eventId': eventId ?? _id('event'),
      'reservationId': reservationId,
      'type': type,
      'itemId': itemId,
      'itemName': itemName,
      'nickname': nickname,
      'roomName': roomName,
      'businessDate': businessDate,
      'sourceDeviceId': _deviceId ?? '',
    };
    if (payload['tenantId'] == null) return;

    await _database.enqueueSyncEvent(
      payload['eventId']!,
      jsonEncode(payload),
    );
    await flushPendingEvents();
  }

  Future<void> flushPendingEvents() async {
    final activeTenantId = _tenantId;
    if (_flushing || activeTenantId == null) return;
    _flushing = true;
    try {
      final events = await _database.getPendingSyncEvents();
      for (final row in events) {
        if (_tenantId != activeTenantId) break;

        final eventId = row['event_id'] as String;
        try {
          final payload = jsonDecode(row['payload'] as String);
          await _functions
              .httpsCallable('createReservationEvent')
              .call(payload);

          if (_tenantId != activeTenantId) break;

          await _database.markSyncEventCompleted(eventId);
        } catch (error, stack) {
          if (_tenantId != activeTenantId) break;

          debugPrint('Reservation cloud sync failed: $error');
          await _database.markSyncEventFailed(eventId, error);
          await FirebaseCrashlytics.instance.recordError(
            error,
            stack,
            reason: 'reservation cloud sync failed',
            fatal: false,
          );
          continue;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<List<Map<String, dynamic>>> getSyncQueueEvents() {
    return _database.getSyncQueueEvents();
  }

  Future<void> retrySyncEvent(String eventId) async {
    await _database.resetSyncEvent(eventId);
    await flushPendingEvents();
  }

  Future<void> retryAllFailedEvents() async {
    await _database.resetFailedSyncEvents();
    await flushPendingEvents();
  }

  String _id(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
  }

  String _reservationId(Reservation reservation) {
    return reservation.cloudId ??
        '${_deviceId ?? 'local'}-${reservation.id ?? _id('reservation')}';
  }
}
