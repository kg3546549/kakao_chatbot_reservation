import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';

class AdminItemsScreen extends StatelessWidget {
  const AdminItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final tenant = session.selectedTenant!;
    final items = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant.tenantId)
        .collection('items')
        .orderBy('name')
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('예약 항목 현황')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('항목을 불러오지 못했습니다.\n${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (docs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('등록된 서버 예약 항목이 없습니다.')),
                  ),
                ),
              for (final item in docs)
                Card(
                  child: ListTile(
                    title: Text(item.data()['name'] ?? item.id),
                    subtitle: Text('최대 ${item.data()['maxCapacity'] ?? 0}명'),
                    trailing: const Icon(Icons.smart_toy_outlined),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
