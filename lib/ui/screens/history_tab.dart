import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../models/reservation.dart';
import '../../providers/bot_provider.dart';
import 'package:intl/intl.dart';

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BotProvider>(
      builder: (context, bot, child) {
        final items = bot.items;

        if (items.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('예약 이력')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('등록된 항목이 없습니다.',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          );
        }

        return DefaultTabController(
          length: items.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('예약 이력'),
              bottom: TabBar(
                isScrollable: true,
                indicatorColor: const Color(0xFF40916C),
                indicatorWeight: 3,
                labelColor: const Color(0xFF1B4332),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                unselectedLabelColor: Colors.grey,
                tabs: items.map((item) => Tab(text: item.name)).toList(),
              ),
            ),
            body: TabBarView(
              children: items
                  .map((item) => HistoryListView(itemId: item.id!))
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class HistoryListView extends StatefulWidget {
  final int itemId;
  const HistoryListView({super.key, required this.itemId});

  @override
  State<HistoryListView> createState() => _HistoryListViewState();
}

class _HistoryListViewState extends State<HistoryListView> {
  DateTime? _filterDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('예약 리스트',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B4332))),
              Row(
                children: [
                  if (_filterDate != null)
                    IconButton(
                      onPressed: () => setState(() => _filterDate = null),
                      icon: const Icon(Icons.refresh,
                          size: 20, color: Colors.grey),
                      tooltip: '필터 해제',
                    ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _filterDate ?? DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (date != null) {
                        setState(() => _filterDate = date);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF40916C),
                      side:
                          const BorderSide(color: Color(0xFF40916C), width: 1),
                      minimumSize: const Size(100, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: Text(
                      _filterDate == null
                          ? '날짜 선택'
                          : DateFormat('MM/dd').format(_filterDate!),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Reservation>>(
            future: DatabaseService()
                .getReservations(itemId: widget.itemId, date: _filterDate),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final reservations = snapshot.data!.reversed.toList();
              if (reservations.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Text(
                      _filterDate == null ? '이력이 없습니다.' : '해당 날짜에 예약이 없습니다.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              final grouped = _groupReservationsByDate(reservations);
              final dates = grouped.keys.toList();

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: dates.length,
                itemBuilder: (context, index) {
                  final date = dates[index];
                  final dailyRes = grouped[date]!;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 4, bottom: 12, top: 16),
                        child: Row(
                          children: [
                            Text(date,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF40916C),
                                    fontSize: 15)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF40916C)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${dailyRes.length}명',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF40916C))),
                            ),
                          ],
                        ),
                      ),
                      Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(color: Colors.grey.shade100),
                        ),
                        child: Column(
                          children: dailyRes.map((res) {
                            final isLast =
                                dailyRes.indexOf(res) == dailyRes.length - 1;
                            return Column(
                              children: [
                                ListTile(
                                  dense: true,
                                  leading: const CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Color(0xFFF8F9FA),
                                    child: Icon(Icons.person,
                                        size: 16, color: Colors.grey),
                                  ),
                                  title: Text(res.nickname,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(res.roomName,
                                      style: const TextStyle(fontSize: 11)),
                                  trailing: Text(
                                      DateFormat('HH:mm').format(res.createdAt),
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.grey)),
                                ),
                                if (!isLast)
                                  Divider(
                                      height: 1,
                                      indent: 56,
                                      color: Colors.grey.shade100),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Map<String, List<Reservation>> _groupReservationsByDate(
      List<Reservation> res) {
    final map = <String, List<Reservation>>{};
    for (var r in res) {
      final dateKey = DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(r.createdAt);
      if (!map.containsKey(dateKey)) map[dateKey] = [];
      map[dateKey]!.add(r);
    }
    return map;
  }
}
