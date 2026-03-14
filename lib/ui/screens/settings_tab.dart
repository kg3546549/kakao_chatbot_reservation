import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bot_provider.dart';
import '../../models/item.dart';
import '../../models/room.dart';
import 'log_viewer_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: Consumer<BotProvider>(
        builder: (context, bot, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionTitle('톡방 권한 설정'),
              if (bot.rooms.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('감지된 톡방이 없습니다.\n예약방에 메시지가 오면 자동으로 등록됩니다.'),
                )),
              ...bot.rooms.map((room) => ListTile(
                title: Text(room.name),
                subtitle: Text('유형: ${room.type.label}'),
                trailing: DropdownButton<RoomType>(
                  value: room.type,
                  onChanged: (type) {
                    if (type != null) bot.updateRoomType(room, type);
                  },
                  items: RoomType.values.map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(type.label),
                  )).toList(),
                ),
              )),
              const Divider(height: 32),
              _buildSectionTitle('시스템 및 진단'),
              ListTile(
                leading: const Icon(Icons.list_alt),
                title: const Text('시스템 로그 확인'),
                subtitle: const Text('챗봇 작동 기록 및 오류 진단'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogViewerScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.battery_saver),
                title: const Text('배터리 최적화 제외 설정'),
                subtitle: Text(bot.isBatteryOptimized ? '설정됨 (안정적)' : '설정 필요 (불안정)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => bot.requestBatteryOptimization(),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active),
                title: const Text('알림 리스너 권한'),
                subtitle: Text(bot.isServiceEnabled ? '활성화됨' : '비활성화됨'),
                trailing: Switch(
                  value: bot.isServiceEnabled,
                  onChanged: (v) => bot.requestPermission(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
    );
  }

  void _showEditItemDialog(BuildContext context, BotProvider bot, Item item) {
    // This is now handled in TemplatesTab, but keeping it here as a fallback or removing it.
    // Let's remove to keep it clean.
  }
}
