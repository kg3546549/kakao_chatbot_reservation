import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../models/item.dart';
import '../models/reservation.dart';
import '../models/room.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BotProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final MethodChannel _channel = const MethodChannel('com.geon.kakao_bot/notification');
  Timer? _cutoffTimer;
  DateTime? _lastBusinessDate;

  List<Item> _items = [];
  List<Room> _rooms = [];
  List<Reservation> _allReservations = [];
  bool _isServiceEnabled = false;
  String _networkStatus = "연결됨";
  bool _isBatteryOptimized = false;

  // Command Aliases
  String cmdReserve = "예약";
  String cmdCancel = "예약취소";
  String cmdStatus = "조회";
  String cmdReset = "초기화";
  String cmdMax = "세팅최대";
  String cmdTemplate = "텍스트변경";
  String cmdTotal = "전체조회";
  String totalTemplate = "📊 전체 예약 현황 📊\n{전체현황}";
  int resetHour = 0;
  int resetMinute = 0;

  List<Item> get items => _items;
  List<Room> get rooms => _rooms;
  List<Reservation> get allReservations => _allReservations;
  bool get isServiceEnabled => _isServiceEnabled;
  String get networkStatus => _networkStatus;
  bool get isBatteryOptimized => _isBatteryOptimized;
  DateTime get businessDate => _businessDateFor(DateTime.now());
  String get resetTimeLabel =>
      '${resetHour.toString().padLeft(2, '0')}:${resetMinute.toString().padLeft(2, '0')}';

  BotProvider() {
    _channel.setMethodCallHandler(_handleMethodCall);
    _startCutoffWatcher();
    _init();
  }

  Future<void> _init() async {
    _items = await _db.getItems();
    _allReservations = await _db.getReservations();
    _rooms = _sortRooms(await _db.getRooms());
    await _loadPreferences();
    
    try {
      _isServiceEnabled = await _channel.invokeMethod('checkPermission');
      _isBatteryOptimized = await _channel.invokeMethod('checkBatteryOptimization');
    } catch (e, stack) {
      debugPrint("Native call failed: $e");
      FirebaseCrashlytics.instance.recordError(
        e, stack,
        reason: 'Native 초기화 실패',
        fatal: false,
      );
    }
    notifyListeners();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    cmdReserve = prefs.getString('cmd_reserve') ?? "예약";
    cmdCancel = prefs.getString('cmd_cancel') ?? "예약취소";
    cmdStatus = prefs.getString('cmd_status') ?? "조회";
    cmdReset = prefs.getString('cmd_reset') ?? "초기화";
    cmdMax = prefs.getString('cmd_max') ?? "세팅최대";
    cmdTemplate = prefs.getString('cmd_template') ?? "텍스트변경";
    cmdTotal = prefs.getString('cmd_total') ?? "전체조회";
    totalTemplate = prefs.getString('total_template') ?? "📊 전체 예약 현황 📊\n{전체현황}";
    resetHour = prefs.getInt('reset_hour') ?? 0;
    resetMinute = prefs.getInt('reset_minute') ?? 0;
  }

  List<Room> _sortRooms(List<Room> rooms) {
    rooms.sort((a, b) {
      if (a.type == b.type) return a.name.compareTo(b.name);
      return a.type.index.compareTo(b.type.index);
    });
    return rooms;
  }

  DateTime _businessDateFor(DateTime dateTime) {
    final cutoffMinutes = (resetHour * 60) + resetMinute;
    final currentMinutes = (dateTime.hour * 60) + dateTime.minute;
    final baseDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (currentMinutes < cutoffMinutes) {
      return baseDate.subtract(const Duration(days: 1));
    }
    return baseDate;
  }

  DateTime _today() {
    return _businessDateFor(DateTime.now());
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _normalizeItemName(String name) => name.trim();

  void _validateItemInput({
    required String name,
    required int maxCapacity,
    int? currentItemId,
  }) {
    final normalized = _normalizeItemName(name);
    if (normalized.isEmpty) {
      throw ArgumentError('항목명은 비어 있을 수 없습니다.');
    }
    if (maxCapacity <= 0) {
      throw ArgumentError('최대 정원은 1명 이상이어야 합니다.');
    }

    final isDuplicate = _items.any(
      (item) => item.id != currentItemId && item.name == normalized,
    );
    if (isDuplicate) {
      throw ArgumentError('이미 존재하는 항목명입니다.');
    }
  }

  void _upsertItemInCache(Item item) {
    final index = _items.indexWhere((existing) => existing.id == item.id);
    if (index == -1) {
      _items = [..._items, item];
      return;
    }

    final updatedItems = [..._items];
    updatedItems[index] = item;
    _items = updatedItems;
  }

  void _removeItemFromCache(int id) {
    _items = _items.where((item) => item.id != id).toList();
    _allReservations = _allReservations.where((reservation) => reservation.itemId != id).toList();
  }

  void _startCutoffWatcher() {
    _lastBusinessDate = businessDate;
    _cutoffTimer?.cancel();
    _cutoffTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final currentBusinessDate = businessDate;
      if (_lastBusinessDate == null || !_isSameDay(_lastBusinessDate!, currentBusinessDate)) {
        _lastBusinessDate = currentBusinessDate;
        notifyListeners();
      }
    });
  }

  Future<void> updateTotalTemplate(String template) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('total_template', template);
    totalTemplate = template;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _init();
  }

  Future<void> requestPermission() async {
    await _channel.invokeMethod('requestPermission');
    await _init();
  }

  Future<void> requestBatteryOptimization() async {
    await _channel.invokeMethod('requestBatteryOptimization');
    await _init();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onNotification') {
      final data = Map<String, dynamic>.from(call.arguments);
      await handleNotification(
        data['roomName'] ?? '',
        data['senderName'] ?? '',
        data['message'] ?? '',
      );
    }
  }

  Future<void> updateCommands({
    required String reserve,
    required String cancel,
    required String status,
    required String reset,
    required String max,
    required String template,
    required String total,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cmd_reserve', reserve);
    await prefs.setString('cmd_cancel', cancel);
    await prefs.setString('cmd_status', status);
    await prefs.setString('cmd_reset', reset);
    await prefs.setString('cmd_max', max);
    await prefs.setString('cmd_template', template);
    await prefs.setString('cmd_total', total);
    
    cmdReserve = reserve;
    cmdCancel = cancel;
    cmdStatus = status;
    cmdReset = reset;
    cmdMax = max;
    cmdTemplate = template;
    cmdTotal = total;
    notifyListeners();
  }

  Future<void> handleNotification(
      String roomName, String senderName, String message) async {
    await _db.addLog("정보", "수신 ($roomName): $message");

    // 1. Room check
    Room? room;
    try {
      room = _rooms.firstWhere((r) => r.name == roomName);
    } catch (e) {
      final newRoom = Room(name: roomName, type: RoomType.general);
      try {
        final roomId = await _db.insertRoom(newRoom);
        _rooms = _sortRooms([..._rooms, Room(id: roomId, name: roomName, type: RoomType.general)]);
      } on DatabaseException {
        final existingRoom = await _db.getRoomByName(roomName);
        if (existingRoom != null) {
          _rooms = _sortRooms([..._rooms.where((r) => r.name != roomName), existingRoom]);
        }
      }
      notifyListeners();
      return;
    }

    if (room.type == RoomType.general) return;

    // 2. Command check
    final trimmedMessage = message.trim();
    if (!trimmedMessage.startsWith('/')) return;

    if (trimmedMessage == '/$cmdTotal') {
      await _sendTotalStatus(roomName, date: _today());
      return;
    }

    final parts = trimmedMessage.split(RegExp(r'\s+'));
    if (parts.length < 2) return;

    final commandWithPrefix = parts[0];
    final commandText = parts[1];
    final itemName = commandWithPrefix.substring(1);

    Item? item;
    try {
      item = _items.firstWhere((i) => i.name == itemName);
    } catch (e) {
      return; 
    }

    // 3. Execute
    if (commandText == cmdReserve) {
      if (parts.length < 3) return;
      final rawNicks = parts.sublist(2).join(' ');
      final nicknames = rawNicks.split(RegExp(r'[,|]')).map((s) => s.trim()).where((s) => s.isNotEmpty);
      final newReservations = <Reservation>[];
      for (var nick in nicknames) {
        final reservation = Reservation(itemId: item.id!, nickname: nick, roomName: roomName);
        final reservationId = await _db.insertReservation(reservation);
        newReservations.add(Reservation(
          id: reservationId,
          itemId: reservation.itemId,
          nickname: reservation.nickname,
          roomName: reservation.roomName,
          createdAt: reservation.createdAt,
        ));
      }
      _allReservations = [..._allReservations, ...newReservations];
      await _sendReply(roomName, await _formatStatus(item, date: _today()));
      notifyListeners();
    } else if (commandText == cmdCancel) {
      if (parts.length < 3) return;
      final rawNicks = parts.sublist(2).join(' ');
      final nicknames = rawNicks.split(RegExp(r'[,|]')).map((s) => s.trim()).where((s) => s.isNotEmpty);
      final targetDate = _today();
      final currentReservations = await _db.getReservations(itemId: item.id!, date: targetDate);
      for (var nick in nicknames) {
        try {
          final res = currentReservations.firstWhere((r) => r.nickname == nick);
          await _db.deleteReservation(res.id!);
          _allReservations = _allReservations.where((reservation) => reservation.id != res.id).toList();
        } catch (_) {}
      }
      await _sendReply(roomName, await _formatStatus(item, date: targetDate));
      notifyListeners();
    } else if (commandText == cmdStatus) {
      await _sendReply(roomName, await _formatStatus(item, date: _today()));
    } else if (commandText == cmdReset) {
      if (room.type != RoomType.admin) return;
      final targetDate = _today();
      final itemId = item.id!;
      await _db.clearReservations(item.id!, date: targetDate);
      _allReservations = _allReservations.where((reservation) {
        return reservation.itemId != itemId || !_isSameDay(reservation.createdAt, targetDate);
      }).toList();
      await _sendReply(roomName, "✅ ${item.name} 항목의 예약이 초기화되었습니다.");
      await _sendReply(roomName, await _formatStatus(item, date: targetDate));
      notifyListeners();
    } else if (commandText == cmdMax) {
      if (room.type != RoomType.admin) return;
      if (parts.length < 3) return;
      final max = int.tryParse(parts[2]);
      if (max != null && max > 0) {
        final updatedItem = Item(
            id: item.id,
            name: item.name,
            maxCapacity: max,
            template: item.template);
        await _db.updateItem(updatedItem);
        _upsertItemInCache(updatedItem);
        await _sendReply(roomName, "✅ ${item.name} 최대 인원이 $max명으로 변경되었습니다.");
        await _sendReply(roomName, await _formatStatus(updatedItem, date: _today()));
        notifyListeners();
      }
    } else if (commandText == cmdTemplate) {
      if (room.type != RoomType.admin) return;
      
      // 명령어 이후의 모든 텍스트를 추출 (줄바꿈 포함)
      // '/메인 텍스트변경 [내용]' 구조에서 [내용] 부분 전체 추출
      final firstSpace = message.indexOf(' ');
      if (firstSpace == -1) return;
      final secondSpace = message.indexOf(' ', firstSpace + 1);
      if (secondSpace == -1) return;
      
      final newTemplate = message.substring(secondSpace + 1).trim();
      if (newTemplate.isEmpty) return;

      final updatedItem = Item(
          id: item.id,
          name: item.name,
          maxCapacity: item.maxCapacity,
          template: newTemplate);
      await _db.updateItem(updatedItem);
      _upsertItemInCache(updatedItem);
      
      await _sendReply(roomName, "✅ ${item.name} 항목의 공지 텍스트가 변경되었습니다.");
      notifyListeners();
    }
  }

  Future<void> updateResetTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reset_hour', time.hour);
    await prefs.setInt('reset_minute', time.minute);
    resetHour = time.hour;
    resetMinute = time.minute;
    _lastBusinessDate = businessDate;
    notifyListeners();
  }

  Future<String> _formatStatus(Item item, {DateTime? date}) async {
    final targetDate = date ?? _today();
    final reservations = await _db.getReservations(itemId: item.id!, date: targetDate);
    String template = item.template;
    if (template.isEmpty) {
      template = "🎊 {날짜} ${item.name} 예약창🎊\n엔트리 : {인원셋팅} MAX\n❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒\n{명단}";
    }

    final dateStr = DateFormat('yyyy년 MM월 dd일').format(targetDate);
    final entryStr = "${reservations.length}/${item.maxCapacity}";

    String listStr = "";
    for (int i = 0; i < reservations.length; i++) {
      listStr += "${i + 1}. ${reservations[i].nickname}\n";
    }

    return template
        .replaceAll('{날짜}', dateStr)
        .replaceAll('{인원셋팅}', entryStr)
        .replaceAll('{현재인원}', reservations.length.toString())
        .replaceAll('{명단}', listStr);
  }

  Future<void> _sendReply(String roomName, String message) async {
    try {
      await _channel.invokeMethod('sendReply', {
        'roomName': roomName,
        'message': message,
      });
      await _db.addLog("성공", "답장 전송 ($roomName)");
    } catch (e, stack) {
      await _db.addLog("오류", "답장 실패 ($roomName): $e");
      FirebaseCrashlytics.instance.recordError(
        e, stack,
        reason: 'sendReply 실패: $roomName',
        fatal: false,
      );
    }
  }

  Future<void> _sendTotalStatus(String roomName, {DateTime? date}) async {
    final targetDate = date ?? _today();
    String listStr = "";
    for (var item in _items) {
      final res = await _db.getReservations(itemId: item.id!, date: targetDate);
      listStr += "- ${item.name}: ${res.length}/${item.maxCapacity}\n";
    }
    
    final finalMessage = totalTemplate.replaceAll('{전체현황}', listStr);
    await _sendReply(roomName, finalMessage);
  }

  Future<void> updateRoomType(Room room, RoomType type) async {
    final updated = Room(id: room.id, name: room.name, type: type);
    await _db.updateRoom(updated);
    _rooms = _sortRooms([
      for (final currentRoom in _rooms)
        if (currentRoom.id == room.id) updated else currentRoom,
    ]);
    notifyListeners();
  }

  Future<void> addItem(String name, int max) async {
    final normalized = _normalizeItemName(name);
    _validateItemInput(name: normalized, maxCapacity: max);
    final itemId = await _db.insertItem(Item(name: normalized, maxCapacity: max));
    _items = [..._items, Item(id: itemId, name: normalized, maxCapacity: max)];
    notifyListeners();
  }

  Future<void> updateItem(Item item) async {
    final normalized = _normalizeItemName(item.name);
    _validateItemInput(
      name: normalized,
      maxCapacity: item.maxCapacity,
      currentItemId: item.id,
    );
    final updatedItem = Item(
      id: item.id,
      name: normalized,
      maxCapacity: item.maxCapacity,
      template: item.template,
    );
    await _db.updateItem(updatedItem);
    _upsertItemInCache(updatedItem);
    notifyListeners();
  }

  Future<void> deleteItem(int id) async {
    await _db.deleteItem(id);
    _removeItemFromCache(id);
    notifyListeners();
  }

  void setNetworkStatus(String status) {
    _networkStatus = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _cutoffTimer?.cancel();
    super.dispose();
  }
}
