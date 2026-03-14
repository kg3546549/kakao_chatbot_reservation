import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bot_provider.dart';
import '../../services/database_service.dart';
import '../../models/item.dart';
import '../../models/reservation.dart';
import 'package:intl/intl.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('예약 대시보드'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<BotProvider>().refresh(),
          ),
        ],
      ),
      body: Consumer<BotProvider>(
        builder: (context, bot, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Date Selection Header
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(
                    DateFormat('yyyy년 MM월 dd일 (E)', 'ko_KR').format(_selectedDate),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.arrow_drop_down),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setState(() {
                        _selectedDate = date;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (bot.networkStatus != "연결됨")
                Card(
                  color: Colors.red.shade100,
                  child: const ListTile(
                    leading: Icon(Icons.error, color: Colors.red),
                    title: Text('네트워크 불안정', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    subtitle: Text('응답 지연이 발생할 수 있습니다.'),
                  ),
                ),
              if (!bot.isServiceEnabled)
                Card(
                  color: Colors.amber.shade100,
                  child: ListTile(
                    leading: const Icon(Icons.warning, color: Colors.amber),
                    title: const Text('알림 리스너 비활성화', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('카톡 알림을 읽으려면 권한이 필요합니다.'),
                    trailing: ElevatedButton(
                      onPressed: () => bot.requestPermission(),
                      child: const Text('설정'),
                    ),
                  ),
                ),
              if (!bot.isBatteryOptimized)
                Card(
                  color: Colors.blue.shade100,
                  child: ListTile(
                    leading: const Icon(Icons.battery_alert, color: Colors.blue),
                    title: const Text('배터리 최적화 활성됨', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('봇이 잠드는 것을 방지하려면 제외 설정이 필요합니다.'),
                    trailing: ElevatedButton(
                      onPressed: () => bot.requestBatteryOptimization(),
                      child: const Text('제외'),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Text('현재 예약 현황', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (bot.items.isEmpty)
                const Center(child: Text('\n등록된 항목이 없습니다.\n설정 탭에서 항목을 추가해주세요.')),
              ...bot.items.map((item) => ItemStatusCard(item: item, selectedDate: _selectedDate)),
            ],
          );
        },
      ),
    );
  }
}

class ItemStatusCard extends StatelessWidget {
  final Item item;
  final DateTime selectedDate;
  const ItemStatusCard({super.key, required this.item, required this.selectedDate});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: DatabaseService().getReservations(itemId: item.id!, date: selectedDate),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        final percent = item.maxCapacity > 0 ? count / item.maxCapacity : 0;
        
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ExpansionTile(
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: LinearProgressIndicator(
              value: percent.toDouble(),
              backgroundColor: Colors.grey.shade300,
              color: percent >= 1.0 ? Colors.red : Colors.blue,
            ),
            trailing: Text('$count / ${item.maxCapacity}'),
            children: [
              if (snapshot.hasData)
                ...snapshot.data!.map((res) => ListTile(
                  dense: true,
                  title: Text(res.nickname),
                  subtitle: Text(res.roomName),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    onPressed: () async {
                      await DatabaseService().deleteReservation(res.id!);
                      context.read<BotProvider>().refresh();
                    },
                  ),
                )),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showManualAddDialog(context, item),
                        icon: const Icon(Icons.add),
                        label: const Text('수동 예약 추가'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showResetConfirmDialog(context, item),
                      icon: const Icon(Icons.refresh),
                      label: const Text('초기화'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _showResetConfirmDialog(BuildContext context, Item item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} 예약 초기화'),
        content: const Text('해당 항목의 모든 예약 정보가 삭제됩니다.\n정말 초기화하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              await DatabaseService().clearReservations(item.id!);
              if (context.mounted) {
                context.read<BotProvider>().refresh();
                Navigator.pop(context);
              }
            },
            child: const Text('초기화', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showManualAddDialog(BuildContext context, Item item) {
    final nickController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} 수동 예약'),
        content: TextField(
          controller: nickController,
          decoration: const InputDecoration(labelText: '닉네임'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              if (nickController.text.isNotEmpty) {
                await DatabaseService().insertReservation(Reservation(
                  itemId: item.id!,
                  nickname: nickController.text,
                  roomName: '수동 등록',
                  createdAt: selectedDate, // Use the selected date for manual reservation
                ));
                if (context.mounted) {
                  context.read<BotProvider>().refresh();
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }
}
