import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
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
      body: Consumer<BotProvider>(
        builder: (context, bot, child) {
          final history = bot.allReservations;
          final vips = _calculateVips(history);
          final todayDist = _calculateTodayDistribution(history, bot.items);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSectionTitle('오늘 항목별 예약 비중'),
              const SizedBox(height: 16),
              if (todayDist.isEmpty)
                _buildEmptyCard('오늘 예약 데이터가 없습니다.')
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SizedBox(
                      height: 200,
                      child: PieChart(
                        PieChartData(
                          sections: todayDist,
                          centerSpaceRadius: 40,
                          sectionsSpace: 4,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 32),
              _buildSectionTitle('방문자 통계 (최근 7일)'),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
                  child: SizedBox(
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
                                final date = DateTime.now().subtract(
                                    Duration(days: 6 - value.toInt()));
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    DateFormat('MM/dd').format(date),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
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
                                const TextStyle(
                                    color: Color(0xFF40916C),
                                    fontWeight: FontWeight.bold),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionTitle('가장 많이 온 손님 (VIP)'),
              const SizedBox(height: 16),
              ...vips.take(5).map((vip) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: Colors.grey.shade100),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            const Color(0xFF40916C).withValues(alpha: 0.1),
                        child: Text('${vips.indexOf(vip) + 1}',
                            style: const TextStyle(
                                color: Color(0xFF40916C),
                                fontWeight: FontWeight.bold)),
                      ),
                      title: Text(vip.nickname,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('총 ${vip.count}회 방문'),
                      trailing:
                          const Icon(Icons.stars, color: Color(0xFF968954)),
                    ),
                  )),
              const SizedBox(height: 100),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Center(
            child: Text(message, style: const TextStyle(color: Colors.grey))),
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

  double _getMaxY(List<Reservation> history) {
    final counts = <int, int>{};
    final now = DateTime.now();
    for (var res in history) {
      final diff = now.difference(res.createdAt).inDays;
      if (diff >= 0 && diff < 7) {
        counts[6 - diff] = (counts[6 - diff] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return 10.0;
    return counts.values.reduce((a, b) => a > b ? a : b).toDouble();
  }

  List<PieChartSectionData> _calculateTodayDistribution(
      List<Reservation> history, List<Item> items) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final counts = <int, int>{};

    for (var res in history) {
      if (DateFormat('yyyy-MM-dd').format(res.createdAt) == today) {
        counts[res.itemId] = (counts[res.itemId] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return [];

    final colors = [
      const Color(0xFF40916C),
      const Color(0xFF52B788),
      const Color(0xFF74C69D),
      const Color(0xFF95D5B2),
      const Color(0xFFB7E4C7),
      const Color(0xFFD8F3DC),
    ];
    int colorIdx = 0;

    return counts.entries.map((e) {
      final item = items.firstWhere((i) => i.id == e.key,
          orElse: () => Item(name: '알 수 없음'));
      final color = colors[colorIdx % colors.length];
      colorIdx++;

      return PieChartSectionData(
        color: color,
        value: e.value.toDouble(),
        title: '${item.name}\n${e.value}명',
        radius: 60,
        titleStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();
  }

  List<BarChartGroupData> _generateBarGroups(List<Reservation> history) {
    // Group by day for the last 7 days
    final counts = <int, int>{};
    final now = DateTime.now();
    for (var res in history) {
      final diff = now.difference(res.createdAt).inDays;
      if (diff >= 0 && diff < 7) {
        counts[6 - diff] = (counts[6 - diff] ?? 0) + 1;
      }
    }

    return List.generate(7, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: (counts[i] ?? 0).toDouble(),
            color: const Color(0xFF40916C),
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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
