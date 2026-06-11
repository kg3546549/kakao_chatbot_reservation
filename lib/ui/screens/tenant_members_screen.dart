import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import 'tenant_invites_screen.dart';

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
      appBar: AppBar(
        title: const Text('멤버 관리'),
        actions: [
          IconButton(
            tooltip: '대기 중인 초대',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TenantInvitesScreen()),
            ),
            icon: const Icon(Icons.key_outlined),
          ),
        ],
      ),
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
                decoration: const InputDecoration(
                  labelText: '초대 대상 계정 이메일',
                  helperText: '이메일은 발송하지 않으며, 생성된 코드를 직접 전달합니다.',
                ),
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
      final inviteId = await session.createTenantInvite(
        email: emailController.text,
        role: role,
      );
      if (inviteId != null && context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('초대 코드 생성 완료'),
            content: SelectableText(
              '$inviteId\n\n초대받은 사용자가 동일한 이메일로 로그인한 뒤 '
              '가게 선택 화면에서 이 코드를 입력해야 합니다. '
              '이 코드를 직접 전달하세요. 코드는 7일간 유효합니다.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    }
    emailController.dispose();
  }
}
