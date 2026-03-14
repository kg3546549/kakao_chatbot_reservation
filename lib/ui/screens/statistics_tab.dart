import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../models/reservation.dart';
import '../../models/item.dart';
import '../../providers/bot_provider.dart';
import 'package:intl/intl.dart';

class StatisticsTab extends StatelessWidget {
  const StatisticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('예약 통계')),
      body: FutureBuilder<List<Reservation>>(
        future: DatabaseService().getReservations(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final history = snapshot.data!;
          final vips = _calculateVips(history);
          final todayDist = _calculateTodayDistribution(history, context.read<BotProvider>().items);
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('오늘 항목별 예약 비중', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (todayDist.isEmpty)
                const Center(child: Text('오늘 예약 데이터가 없습니다.'))
              else
                SizedBox(
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      sections: todayDist,
                      centerSpaceRadius: 40,
                      sectionsSpace: 2,
                    ),
                  ),
                ),
              const SizedBox(height: 32),
              const Text('방문자 통계 (최근 7일)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 250,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: _getMaxY(history) + 5,
                    barGroups: _generateBarGroups(history),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final date = DateTime.now().subtract(Duration(days: 6 - value.toInt()));
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                DateFormat('MM/dd').format(date),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        tooltipBgColor: Colors.transparent,
                        tooltipPadding: EdgeInsets.zero,
                        tooltipMargin: 8,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                            rod.toY.toInt().toString(),
                            const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('가장 많이 온 손님 (VIP)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...vips.take(5).map((vip) => ListTile(
                leading: CircleAvatar(child: Text(vip.count.toString())),
                title: Text(vip.nickname),
                trailing: const Icon(Icons.star, color: Colors.amber),
              )),
            ],
          );
        },
      ),
    );
  }

  List<VipInfo> _calculateVips(List<Reservation> history) {
    final counts = <String, int>{};
    for (var res in history) {
      counts[res.nickname] = (counts[res.nickname] ?? 0) + 1;
    }
    final list = counts.entries.map((e) => VipInfo(e.key, e.value)).toList();
    list.sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  List<PieChartSectionData> _calculateTodayDistribution(List<Reservation> history, List<Item> items) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final counts = <int, int>{};
    
    for (var res in history) {
      if (DateFormat('yyyy-MM-dd').format(res.createdAt) == today) {
        counts[res.itemId] = (counts[res.itemId] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return [];

    final colors = [Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple, Colors.teal];
    int colorIdx = 0;

    return counts.entries.map((e) {
      final item = items.firstWhere((i) => i.id == e.key, orElse: () => Item(name: 'Unknown'));
      final color = colors[colorIdx % colors.length];
      colorIdx++;
      
      return PieChartSectionData(
        color: color,
        value: e.value.toDouble(),
        title: '${item.name}\n(${e.value})',
        radius: 50,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();
  }

  double _getMaxY(List<Reservation> history) {
    final counts = <int, int>{};
    final now = DateTime.now();
    for (var res in history) {
      final diff = now.difference(res.createdAt).inDays;
      if (diff < 7) {
        counts[6 - diff] = (counts[6 - diff] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return 10.0;
    return counts.values.reduce((a, b) => a > b ? a : b).toDouble();
  }

  List<BarChartGroupData> _generateBarGroups(List<Reservation> history) {
    // Group by day for the last 7 days
    final counts = <int, int>{};
    final now = DateTime.now();
    for (var res in history) {
      final diff = now.difference(res.createdAt).inDays;
      if (diff < 7) {
        counts[6 - diff] = (counts[6 - diff] ?? 0) + 1;
      }
    }

    return List.generate(7, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: (counts[i] ?? 0).toDouble(),
            color: Colors.indigo,
            width: 16,
            borderRadius: BorderRadius.circular(4),
          )
        ],
      );
    });
  }
}

class VipInfo {
  final String nickname;
  final int count;
  VipInfo(this.nickname, this.count);
}
