import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';

class AdminHistoryScreen extends StatelessWidget {
  const AdminHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tenant = context.watch<SessionProvider>().selectedTenant!;
    final events = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant.tenantId)
        .collection('reservationEvents')
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('예약 변경 이력')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: events,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('이력을 불러오지 못했습니다.\n${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('예약 변경 이력이 없습니다.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final timestamp = data['createdAt'];
              final createdAt =
                  timestamp is Timestamp ? timestamp.toDate() : null;
              return Card(
                child: ListTile(
                  leading: _EventIcon(type: data['type'] ?? ''),
                  title: Text(_eventTitle(data)),
                  subtitle: Text(
                    '${data['businessDate'] ?? ''} · ${data['roomName'] ?? ''}',
                  ),
                  trailing: createdAt == null
                      ? null
                      : Text(DateFormat('MM/dd HH:mm').format(createdAt)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _eventTitle(Map<String, dynamic> data) {
    final nickname = data['nickname']?.toString() ?? '';
    final itemName = data['itemName']?.toString() ?? '';
    switch (data['type']) {
      case 'created':
        return '$nickname 예약 등록 · $itemName';
      case 'cancelled':
        return '$nickname 예약 취소 · $itemName';
      case 'updated':
        return '$nickname 예약 수정 · $itemName';
      case 'reset':
        return '$itemName 예약 초기화';
      default:
        return '예약 변경 · $itemName';
    }
  }
}

class _EventIcon extends StatelessWidget {
  final String type;

  const _EventIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      'created' => const Icon(Icons.add_circle, color: Color(0xFF40916C)),
      'cancelled' => const Icon(Icons.cancel, color: Colors.orange),
      'updated' => const Icon(Icons.edit, color: Colors.blue),
      'reset' => const Icon(Icons.restart_alt, color: Colors.red),
      _ => const Icon(Icons.history),
    };
  }
}
