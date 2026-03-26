import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bot_provider.dart';
import '../../models/item.dart';
import '../../models/room.dart';
import 'log_viewer_screen.dart';
import 'command_settings_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: Consumer<BotProvider>(
        builder: (context, bot, child) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSectionTitle('톡방 권한 설정'),
              const SizedBox(height: 8),
              if (bot.rooms.isEmpty)
                _buildEmptyCard('감지된 톡방이 없습니다.\n예약방에 메시지가 오면 자동으로 등록됩니다.'),
              
              // 1. 설정된 방 (예약방, 관리자방)
              ...bot.rooms.where((r) => r.type != RoomType.general).map((room) => _buildRoomCard(bot, room)),
              
              // 2. 설정 안 된 방 (일반방) - 아코디언 처리
              if (bot.rooms.any((r) => r.type == RoomType.general))
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: ExpansionTile(
                    shape: const RoundedRectangleBorder(side: BorderSide.none),
                    title: Text('기타 방 목록 (${bot.rooms.where((r) => r.type == RoomType.general).length}개)', 
                      style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                    children: bot.rooms
                        .where((r) => r.type == RoomType.general)
                        .map((room) => _buildRoomTile(bot, room))
                        .toList(),
                  ),
                ),
              
              const SizedBox(height: 32),
              _buildSectionTitle('시스템 및 진단'),
              const SizedBox(height: 8),
              _buildSystemCard(
                icon: Icons.schedule_outlined,
                title: '예약 기준일 전환 시간',
                subtitle: '매일 ${bot.resetTimeLabel}에 카톡 예약 기준일이 바뀝니다.',
                onTap: () => _showResetTimePicker(context, bot),
                trailing: Text(
                  bot.resetTimeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF40916C),
                  ),
                ),
              ),
              _buildSystemCard(
                icon: Icons.settings_suggest_outlined,
                title: '명령어 단어 설정',
                subtitle: '예약, 취소 등 명령어 단어 커스텀',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommandSettingsScreen())),
              ),
              _buildSystemCard(
                icon: Icons.list_alt_outlined,
                title: '시스템 로그 확인',
                subtitle: '봇 작동 기록 및 오류 진단',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogViewerScreen())),
              ),
              _buildSystemCard(
                icon: Icons.battery_saver_outlined,
                title: '배터리 최적화 제외 설정',
                subtitle: bot.isBatteryOptimized ? '설정됨 (안정적)' : '설정 필요 (불안정)',
                onTap: () => bot.requestBatteryOptimization(),
                trailing: Icon(
                  bot.isBatteryOptimized ? Icons.check_circle : Icons.warning,
                  color: bot.isBatteryOptimized ? const Color(0xFF40916C) : Colors.orange,
                  size: 20,
                ),
              ),
              _buildSystemCard(
                icon: Icons.notifications_active_outlined,
                title: '알림 리스너 권한',
                subtitle: bot.isServiceEnabled ? '활성화됨' : '비활성화됨',
                onTap: () => bot.requestPermission(),
                trailing: Switch(
                  value: bot.isServiceEnabled,
                  activeColor: const Color(0xFF40916C),
                  onChanged: (v) => bot.requestPermission(),
                ),
              ),
              const SizedBox(height: 100),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showResetTimePicker(BuildContext context, BotProvider bot) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: bot.resetHour, minute: bot.resetMinute),
    );
    if (picked == null) return;
    await bot.updateResetTime(picked);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('예약 기준일 전환 시간이 ${bot.resetTimeLabel}로 저장되었습니다.')),
      );
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B4332))),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Center(child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13))),
    );
  }

  Widget _buildRoomCard(BotProvider bot, Room room) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: Color(0xFF40916C), width: 0.5),
      ),
      child: _buildRoomTile(bot, room),
    );
  }

  Widget _buildRoomTile(BotProvider bot, Room room) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      subtitle: Text('현재: ${room.type.label}', style: const TextStyle(fontSize: 12)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButton<RoomType>(
          value: room.type,
          underline: const SizedBox(),
          style: const TextStyle(fontSize: 13, color: Color(0xFF40916C), fontWeight: FontWeight.bold),
          onChanged: (type) {
            if (type != null) bot.updateRoomType(room, type);
          },
          items: RoomType.values.map((type) => DropdownMenuItem(
            value: type,
            child: Text(type.label),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildSystemCard({required IconData icon, required String title, required String subtitle, required VoidCallback onTap, Widget? trailing}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF40916C).withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF40916C), size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      ),
    );
  }
}
