import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/item.dart';
import '../models/reservation.dart';
import '../models/room.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';

class BotProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final MethodChannel _channel = const MethodChannel('com.geon.kakao_bot/notification');

  List<Item> _items = [];
  List<Room> _rooms = [];
  bool _isServiceEnabled = false;
  String _networkStatus = "연결됨";

  List<Item> get items => _items;
  List<Room> get rooms => _rooms;
  bool get isServiceEnabled => _isServiceEnabled;
  String get networkStatus => _networkStatus;

  BotProvider() {
    _channel.setMethodCallHandler(_handleMethodCall);
    _init();
  }

  bool _isBatteryOptimized = false;

  bool get isBatteryOptimized => _isBatteryOptimized;

  Future<void> _init() async {
    _items = await _db.getItems();
    final allRooms = await _db.getRooms();
    // Sort: Reservation/Admin first, then General
    allRooms.sort((a, b) {
      if (a.type == b.type) return a.name.compareTo(b.name);
      return a.type.index.compareTo(b.type.index); 
    });
    _rooms = allRooms;
    _isServiceEnabled = await _channel.invokeMethod('checkPermission');
    _isBatteryOptimized = await _channel.invokeMethod('checkBatteryOptimization');
    notifyListeners();
  }

  Future<void> requestPermission() async {
    await _channel.invokeMethod('requestPermission');
    await _init();
  }

  Future<void> requestBatteryOptimization() async {
    await _channel.invokeMethod('requestBatteryOptimization');
    await _init();
  }

  Future<void> refresh() async {
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

  Future<void> handleNotification(
      String roomName, String senderName, String message) async {
    await _db.addLog("정보", "수신 ($roomName): $message");

    // 1. Room check
    Room? room;
    try {
      room = _rooms.firstWhere((r) => r.name == roomName);
    } catch (e) {
      // New room detected
      final newRoom = Room(name: roomName, type: RoomType.general);
      await _db.insertRoom(newRoom);
      _rooms = await _db.getRooms();
      notifyListeners();
      return;
    }

    if (room.type == RoomType.general) return;

    // 2. Command check
    if (!message.startsWith('/')) return;

    // Special command: /전체조회
    if (message.startsWith('/전체조회')) {
      await _sendTotalStatus(roomName);
      return;
    }

    final parts = message.split(' ');
    if (parts.length < 2) return;

    final commandWithPrefix = parts[0];
    final command = parts[1];
    final itemName = commandWithPrefix.substring(1);

    Item? item;
    try {
      item = _items.firstWhere((i) => i.name == itemName);
    } catch (e) {
      return; // Unknown item
    }

    // 3. Execute
    switch (command) {
      case '예약':
        if (parts.length < 3) return;
        final rawNicks = parts.sublist(2).join(' ');
        final nicknames = rawNicks.split(RegExp(r'[,|]')).map((s) => s.trim()).where((s) => s.isNotEmpty);
        for (var nick in nicknames) {
          await _db.insertReservation(Reservation(
              itemId: item.id!, nickname: nick, roomName: roomName));
        }
        await _sendReply(roomName, await _formatStatus(item));
        break;
      case '예약취소':
        if (parts.length < 3) return;
        final rawNicks = parts.sublist(2).join(' ');
        final nicknames = rawNicks.split(RegExp(r'[,|]')).map((s) => s.trim()).where((s) => s.isNotEmpty);
        final currentReservations = await _db.getReservations(itemId: item.id!);
        for (var nick in nicknames) {
          try {
            final res = currentReservations.firstWhere((r) => r.nickname == nick);
            await _db.deleteReservation(res.id!);
          } catch (e) {
            // Nickname not found in reservations
          }
        }
        await _sendReply(roomName, await _formatStatus(item));
        break;
      case '조회':
        await _sendReply(roomName, await _formatStatus(item));
        break;
      case '초기화':
        if (room.type != RoomType.admin) return;
        await _db.clearReservations(item.id!);
        // 초기화 메시지 전송 후, 비어있는 새로운 예약창 전송
        await _sendReply(roomName, "✅ ${item.name} 항목의 예약이 초기화되었습니다.");
        await _sendReply(roomName, await _formatStatus(item));
        break;
      case '세팅최대':
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
          _items = await _db.getItems();
          await _sendReply(roomName, "✅ ${item.name} 최대 인원이 $max명으로 변경되었습니다.");
          // 설정 변경 후 현재 상태 전송
          await _sendReply(roomName, await _formatStatus(item));
          notifyListeners();
        }
        break;
      case '텍스트변경':
        if (room.type != RoomType.admin) return;
        if (parts.length < 3) return;
        final newTemplate = parts.sublist(2).join(' ');
        final updatedItem = Item(
            id: item.id,
            name: item.name,
            maxCapacity: item.maxCapacity,
            template: newTemplate);
        await _db.updateItem(updatedItem);
        _items = await _db.getItems();
        await _sendReply(roomName, "✅ ${item.name} 공지 텍스트가 변경되었습니다.");
        notifyListeners();
        break;
    }
  }

  Future<String> _formatStatus(Item item) async {
    final reservations = await _db.getReservations(itemId: item.id!);
    String template = item.template;
    if (template.isEmpty) {
      template = "🎊 {날짜} ${item.name} 예약창🎊\n엔트리 : {인원셋팅} MAX\n❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒ ❒\n{명단}";
    }

    final dateStr = DateFormat('yyyy년 MM월 dd일').format(DateTime.now());
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
    } catch (e) {
      await _db.addLog("오류", "답장 실패 ($roomName): $e");
    }
  }
  Future<void> _sendTotalStatus(String roomName) async {
    String status = "📊 전체 예약 현황 📊\n";
    for (var item in _items) {
      final res = await _db.getReservations(itemId: item.id!);
      status += "- ${item.name}: ${res.length}/${item.maxCapacity}\n";
    }
    await _sendReply(roomName, status);
  }

  Future<void> updateRoomType(Room room, RoomType type) async {
    final updated = Room(id: room.id, name: room.name, type: type);
    await _db.updateRoom(updated);
    _rooms = await _db.getRooms();
    notifyListeners();
  }

  Future<void> addItem(String name, int max) async {
    await _db.insertItem(Item(name: name, maxCapacity: max));
    _items = await _db.getItems();
    notifyListeners();
  }

  Future<void> updateItem(Item item) async {
    await _db.updateItem(item);
    _items = await _db.getItems();
    notifyListeners();
  }

  Future<void> deleteItem(int id) async {
    await _db.deleteItem(id);
    _items = await _db.getItems();
    notifyListeners();
  }

  void setNetworkStatus(String status) {
    _networkStatus = status;
    notifyListeners();
  }
}
