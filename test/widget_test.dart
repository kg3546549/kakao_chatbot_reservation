import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:kakao_reservation_bot/models/item.dart';
import 'package:kakao_reservation_bot/models/reservation.dart';
import 'package:kakao_reservation_bot/models/room.dart';
import 'package:kakao_reservation_bot/providers/bot_provider.dart';
import 'package:kakao_reservation_bot/ui/screens/settings_tab.dart';

class TestBotProvider extends ChangeNotifier implements BotProvider {
  @override
  List<Item> get items => [];

  @override
  List<Room> get rooms => [];

  @override
  List<Reservation> get allReservations => [];

  @override
  bool get isServiceEnabled => true;

  @override
  String get networkStatus => '연결됨';

  @override
  bool get isBatteryOptimized => true;

  @override
  int resetHour = 0;

  @override
  int resetMinute = 0;

  @override
  DateTime get businessDate => DateTime(2026, 3, 27);

  @override
  String get resetTimeLabel => '00:00';

  @override
  String cmdReserve = '예약';

  @override
  String cmdCancel = '예약취소';

  @override
  String cmdStatus = '조회';

  @override
  String cmdReset = '초기화';

  @override
  String cmdMax = '세팅최대';

  @override
  String cmdTemplate = '텍스트변경';

  @override
  String cmdTotal = '전체조회';

  @override
  String totalTemplate = '📊 전체 예약 현황 📊\n{전체현황}';

  @override
  Future<void> addItem(String name, int max) async {}

  @override
  Future<void> deleteItem(int id) async {}

  @override
  Future<void> handleNotification(String roomName, String senderName, String message) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> requestBatteryOptimization() async {}

  @override
  Future<void> requestPermission() async {}

  @override
  void setNetworkStatus(String status) {}

  @override
  Future<void> updateResetTime(TimeOfDay time) async {
    resetHour = time.hour;
    resetMinute = time.minute;
  }

  @override
  Future<void> updateCommands({
    required String reserve,
    required String cancel,
    required String status,
    required String reset,
    required String max,
    required String template,
    required String total,
  }) async {}

  @override
  Future<void> updateItem(Item item) async {}

  @override
  Future<void> updateRoomType(Room room, RoomType type) async {}

  @override
  Future<void> updateTotalTemplate(String template) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings tab renders system sections', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<BotProvider>.value(
        value: TestBotProvider(),
        child: const MaterialApp(home: SettingsTab()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('톡방 권한 설정'), findsOneWidget);
    expect(find.text('시스템 및 진단'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
  });
}
