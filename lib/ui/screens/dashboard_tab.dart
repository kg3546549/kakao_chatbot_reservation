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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              // Date Selection Header
              GestureDetector(
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
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF40916C).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.calendar_today, color: Color(0xFF40916C), size: 20),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('예약 날짜 선택', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(
                            DateFormat('yyyy년 MM월 dd일 (E)', 'ko_KR').format(_selectedDate),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              if (bot.networkStatus != "연결됨")
                _buildAlertCard(
                  context,
                  icon: Icons.wifi_off,
                  title: '네트워크 불안정',
                  subtitle: '응답 지연이 발생할 수 있습니다.',
                  color: Colors.red,
                ),
              if (!bot.isServiceEnabled)
                _buildAlertCard(
                  context,
                  icon: Icons.notifications_none,
                  title: '알림 권한 필요',
                  subtitle: '카톡 알림을 읽으려면 권한이 필요합니다.',
                  color: Colors.orange,
                  actionLabel: '설정하기',
                  onAction: () => bot.requestPermission(),
                ),
              if (!bot.isBatteryOptimized)
                _buildAlertCard(
                  context,
                  icon: Icons.battery_saver,
                  title: '배터리 최적화 활성',
                  subtitle: '봇이 잠드는 것을 방지하려면 제외가 필요합니다.',
                  color: Colors.blue,
                  actionLabel: '제외하기',
                  onAction: () => bot.requestBatteryOptimization(),
                ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('진행 중인 예약', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B4332))),
              ),
              
              if (bot.items.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      children: [
                        Icon(Icons.add_circle_outline, size: 60, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text('등록된 항목이 없습니다.\n[항목 설정]에서 추가해주세요.', 
                          textAlign: TextAlign.center, 
                          style: TextStyle(color: Colors.grey)
                        ),
                      ],
                    ),
                  ),
                ),
              ...bot.items.map((item) => ItemStatusCard(item: item, selectedDate: _selectedDate)),
              const SizedBox(height: 100),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAlertCard(BuildContext context, {
    required IconData icon, 
    required String title, 
    required String subtitle, 
    required Color color,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: color.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: color.withOpacity(0.1)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
        trailing: onAction != null ? TextButton(
          onPressed: onAction,
          child: Text(actionLabel!, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ) : null,
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
        final isFull = percent >= 1.0;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: ExpansionTile(
              backgroundColor: Colors.white,
              collapsedBackgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(side: BorderSide.none),
              title: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: (isFull ? Colors.red : const Color(0xFF40916C)).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: isFull ? Colors.red : const Color(0xFF40916C),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1B4332))),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percent.toDouble(),
                            backgroundColor: Colors.grey.shade100,
                            color: isFull ? Colors.red : const Color(0xFF40916C),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('정원 ${item.maxCapacity}명', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const Icon(Icons.keyboard_arrow_down, size: 20),
                ],
              ),
              children: [
                if (snapshot.hasData && snapshot.data!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: snapshot.data!.map((res) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFF40916C).withOpacity(0.1),
                          child: Text('${snapshot.data!.indexOf(res) + 1}', style: const TextStyle(fontSize: 10, color: Color(0xFF40916C))),
                        ),
                        title: Text(res.nickname, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(res.roomName, style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.red),
                          onPressed: () async {
                            await DatabaseService().deleteReservation(res.id!);
                            context.read<BotProvider>().refresh();
                          },
                        ),
                      )).toList(),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('예약자가 없습니다.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ),
                
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _showManualAddDialog(context, item),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF40916C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('수동 추가', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: () => _showResetConfirmDialog(context, item),
                          icon: const Icon(Icons.refresh, color: Colors.red),
                          tooltip: '초기화',
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showResetConfirmDialog(BuildContext context, Item item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} 초기화'),
        content: Text(
          '${DateFormat('yyyy-MM-dd').format(selectedDate)} 날짜의 모든 예약 정보가 삭제됩니다.\n정말 초기화하시겠습니까?',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseService().clearReservations(item.id!, date: selectedDate);
              if (context.mounted) {
                context.read<BotProvider>().refresh();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${item.name} 초기화 완료')),
                );
              }
            },
            child: const Text('날짜 초기화', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
