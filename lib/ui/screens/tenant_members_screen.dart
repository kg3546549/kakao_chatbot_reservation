import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';

class TenantMembersScreen extends StatelessWidget {
  const TenantMembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final tenant = session.selectedTenant!;
    final members = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant.tenantId)
        .collection('members')
        .where('status', isEqualTo: 'active')
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('멤버 관리')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: members,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('멤버를 불러오지 못했습니다.\n${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final member in snapshot.data!.docs)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(member.data()['email'] ?? member.id),
                    subtitle: Text(member.data()['role'] ?? 'viewer'),
                    trailing: member.id == session.user?.uid
                        ? null
                        : IconButton(
                            tooltip: '멤버 제거',
                            onPressed: session.busy
                                ? null
                                : () => session.removeTenantMember(member.id),
                            icon: const Icon(Icons.person_remove_outlined),
                          ),
                  ),
                ),
              if (session.errorMessage != null)
                Text(
                  session.errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: session.busy ? null : () => _showAddMember(context, session),
        icon: const Icon(Icons.person_add),
        label: const Text('멤버 추가'),
      ),
    );
  }

  Future<void> _showAddMember(
    BuildContext context,
    SessionProvider session,
  ) async {
    final emailController = TextEditingController();
    var role = 'manager';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('멤버 추가'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '가입된 이메일'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: '역할'),
                items: const [
                  DropdownMenuItem(value: 'manager', child: Text('관리자')),
                  DropdownMenuItem(value: 'viewer', child: Text('조회 전용')),
                  DropdownMenuItem(value: 'botDevice', child: Text('예약봇 기기')),
                ],
                onChanged: (value) => setState(() => role = value ?? role),
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
      ),
    );
    if (result == true && emailController.text.trim().isNotEmpty) {
      await session.addTenantMember(email: emailController.text, role: role);
    }
    emailController.dispose();
  }
}
