import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import 'tenant_members_screen.dart';
import 'admin_analytics_screen.dart';
import 'admin_history_screen.dart';
import 'admin_items_screen.dart';
import 'tenant_devices_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final tenant = session.selectedTenant!;
    final canManage = ['owner', 'manager'].contains(tenant.role);
    final reservations = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant.tenantId)
        .collection('currentReservations')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text('${tenant.tenantName} 관리자'),
        actions: [
          IconButton(
            tooltip: '연결 기기 관리',
            onPressed: canManage
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TenantDevicesScreen(),
                      ),
                    )
                : null,
            icon: const Icon(Icons.devices_outlined),
          ),
          IconButton(
            tooltip: '예약 항목 현황',
            onPressed: canManage
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminItemsScreen(),
                      ),
                    )
                : null,
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
          IconButton(
            tooltip: '예약 이력',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminHistoryScreen()),
            ),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: '예약 분석',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminAnalyticsScreen()),
            ),
            icon: const Icon(Icons.analytics_outlined),
          ),
          IconButton(
            tooltip: '멤버 관리',
            onPressed: tenant.role == 'owner'
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TenantMembersScreen(),
                      ),
                    )
                : null,
            icon: const Icon(Icons.group_outlined),
          ),
          IconButton(
            tooltip: '모드 변경',
            onPressed: session.leaveMode,
            icon: const Icon(Icons.swap_horiz),
          ),
          IconButton(
            tooltip: '로그아웃',
            onPressed: session.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: reservations,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('예약 정보를 불러오지 못했습니다.\n${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final itemCount =
              docs.map((doc) => doc.data()['itemId']).toSet().length;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      label: '최근 예약',
                      value: '${docs.length}',
                      icon: Icons.event_available,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      label: '예약 항목',
                      value: '$itemCount',
                      icon: Icons.category_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                '현재 예약 현황',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (docs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('현재 예약이 없습니다.')),
                  ),
                ),
              for (final doc in docs)
                _ReservationTile(
                  data: doc.data(),
                  onCancel: session.busy || !canManage
                      ? null
                      : () => _confirmCancel(context, session, doc.data()),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: session.busy || !canManage
            ? null
            : () => _showCreateDialog(context, session),
        icon: const Icon(Icons.add),
        label: const Text('예약 추가'),
      ),
    );
  }

  Future<void> _showCreateDialog(
    BuildContext context,
    SessionProvider session,
  ) async {
    final itemController = TextEditingController();
    final nicknameController = TextEditingController();
    final roomController = TextEditingController(text: '관리자 직접 등록');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('예약 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: itemController,
              decoration: const InputDecoration(labelText: '예약 항목'),
            ),
            TextField(
              controller: nicknameController,
              decoration: const InputDecoration(labelText: '예약자 이름'),
            ),
            TextField(
              controller: roomController,
              decoration: const InputDecoration(labelText: '등록 경로'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    if (result == true &&
        itemController.text.trim().isNotEmpty &&
        nicknameController.text.trim().isNotEmpty) {
      await session.createAdminReservation(
        itemName: itemController.text,
        nickname: nicknameController.text,
        roomName: roomController.text,
      );
    }
    itemController.dispose();
    nicknameController.dispose();
    roomController.dispose();
  }

  Future<void> _confirmCancel(
    BuildContext context,
    SessionProvider session,
    Map<String, dynamic> reservation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('예약 취소'),
        content: Text('${reservation['nickname']}님의 예약을 취소하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('예약 취소'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await session.cancelAdminReservation(reservation);
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF40916C)),
            const SizedBox(height: 12),
            Text(value,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onCancel;

  const _ReservationTile({required this.data, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final nickname = data['nickname'] ?? '';
    final itemId = data['itemId'] ?? '';
    final itemName = data['itemName'] ?? '';
    final date = data['businessDate'] ?? '';
    return Card(
      child: ListTile(
        leading: const Icon(
          Icons.person,
          color: Color(0xFF40916C),
        ),
        title: Text(nickname.toString().isEmpty ? '이름 없음' : nickname),
        subtitle: Text(
          '$date · ${itemName.toString().isEmpty ? '항목 $itemId' : itemName}',
        ),
        trailing: IconButton(
          tooltip: '예약 취소',
          onPressed: onCancel,
          icon: const Icon(Icons.cancel_outlined),
        ),
      ),
    );
  }
}
