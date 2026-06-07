import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';

class AdminAnalyticsScreen extends StatelessWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tenant = context.watch<SessionProvider>().selectedTenant!;
    final stats = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant.tenantId)
        .collection('dailyStats')
        .orderBy('businessDate', descending: true)
        .limit(30)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('예약 분석')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stats,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('통계를 불러오지 못했습니다.\n${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final created = docs.fold<int>(
            0,
            (sum, doc) => sum + _int(doc.data()['createdCount']),
          );
          final cancelled = docs.fold<int>(
            0,
            (sum, doc) => sum + _int(doc.data()['cancelledCount']),
          );

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: '최근 30일 예약',
                      value: created,
                      color: const Color(0xFF40916C),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: '최근 30일 취소',
                      value: cancelled,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                '일별 현황',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (docs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('집계된 데이터가 없습니다.')),
                  ),
                ),
              for (final doc in docs)
                Card(
                  child: ListTile(
                    title: Text(doc.data()['businessDate'] ?? doc.id),
                    subtitle: Text(
                      '예약 ${_int(doc.data()['createdCount'])}건 · '
                      '취소 ${_int(doc.data()['cancelledCount'])}건',
                    ),
                    trailing: Text(
                      '순증 ${_int(doc.data()['activeDelta'])}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static int _int(dynamic value) => value is num ? value.toInt() : 0;
}

class _MetricCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(label, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
