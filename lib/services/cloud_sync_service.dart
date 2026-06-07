import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

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

  void configure({required String tenantId, required String deviceId}) {
    _tenantId = tenantId;
    _deviceId = deviceId;
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => flushPendingEvents(),
    );
    unawaited(flushPendingEvents());
  }

  void clear() {
    _tenantId = null;
    _deviceId = null;
    _retryTimer?.cancel();
    _retryTimer = null;
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

  Future<void> _publish({
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
      'eventId': _id('event'),
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
    if (_flushing || _tenantId == null) return;
    _flushing = true;
    try {
      final events = await _database.getPendingSyncEvents();
      for (final row in events) {
        final eventId = row['event_id'] as String;
        try {
          final payload = jsonDecode(row['payload'] as String);
          await _functions
              .httpsCallable('createReservationEvent')
              .call(payload);
          await _database.markSyncEventCompleted(eventId);
        } catch (error, stack) {
          debugPrint('Reservation cloud sync failed: $error');
          await _database.markSyncEventFailed(eventId, error);
          await FirebaseCrashlytics.instance.recordError(
            error,
            stack,
            reason: 'reservation cloud sync failed',
            fatal: false,
          );
          break;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  String _id(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
  }

  String _reservationId(Reservation reservation) {
    return '${_deviceId ?? 'local'}-${reservation.id ?? _id('reservation')}';
  }
}
