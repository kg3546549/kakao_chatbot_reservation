import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../models/reservation.dart';
import '../../models/item.dart';
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
            body: const Center(child: Text('등록된 항목이 없습니다.')),
          );
        }

        return DefaultTabController(
          length: items.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('예약 이력'),
              bottom: TabBar(
                isScrollable: true,
                tabs: items.map((item) => Tab(text: item.name)).toList(),
              ),
            ),
            body: TabBarView(
              children: items.map((item) => HistoryListView(itemId: item.id!)).toList(),
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
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_filterDate != null)
                TextButton.icon(
                  onPressed: () => setState(() => _filterDate = null),
                  icon: const Icon(Icons.clear),
                  label: const Text('필터 해제'),
                ),
              ElevatedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _filterDate ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (date != null) {
                    setState(() => _filterDate = date);
                  }
                },
                icon: const Icon(Icons.calendar_month),
                label: Text(_filterDate == null ? '날짜 선택' : DateFormat('yyyy-MM-dd').format(_filterDate!)),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Reservation>>(
            future: DatabaseService().getReservations(itemId: widget.itemId, date: _filterDate),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final reservations = snapshot.data!.reversed.toList();
              if (reservations.isEmpty) return const Center(child: Text('해당 조건의 이력이 없습니다.'));

              final grouped = _groupReservationsByDate(reservations);
              final dates = grouped.keys.toList();

              return ListView.builder(
                itemCount: dates.length,
                itemBuilder: (context, index) {
                  final date = dates[index];
                  final dailyRes = grouped[date]!;
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.grey.shade200,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(date, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                            Text('총 ${dailyRes.length}명', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      ...dailyRes.map((res) => ListTile(
                        dense: true,
                        title: Text(res.nickname, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(res.roomName),
                        trailing: Text(DateFormat('HH:mm').format(res.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      )),
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

  Map<String, List<Reservation>> _groupReservationsByDate(List<Reservation> res) {
    final map = <String, List<Reservation>>{};
    for (var r in res) {
      final dateKey = DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(r.createdAt);
      if (!map.containsKey(dateKey)) map[dateKey] = [];
      map[dateKey]!.add(r);
    }
    return map;
  }
}
