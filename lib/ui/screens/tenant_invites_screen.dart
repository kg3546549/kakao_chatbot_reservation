import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';

class TenantInvitesScreen extends StatefulWidget {
  const TenantInvitesScreen({super.key});

  @override
  State<TenantInvitesScreen> createState() => _TenantInvitesScreenState();
}

class _TenantInvitesScreenState extends State<TenantInvitesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _invites = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final invites = await context.read<SessionProvider>().listTenantInvites();
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('초대 목록을 불러오지 못했습니다: $error')),
      );
    }
  }

  Future<void> _revoke(String inviteId) async {
    setState(() => _loading = true);
    await context.read<SessionProvider>().revokeTenantInvite(inviteId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('대기 중인 초대'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_invites.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: Text('대기 중인 초대가 없습니다.')),
                    ),
                  ),
                for (final invite in _invites)
                  Card(
                    child: ListTile(
                      title: Text(invite['email'] ?? ''),
                      subtitle: Text(
                        '${invite['role'] ?? 'viewer'} · '
                        '${_expiresAt(invite['expiresAt'])}',
                      ),
                      trailing: IconButton(
                        tooltip: '초대 취소',
                        onPressed: () => _revoke(invite['inviteId'].toString()),
                        icon: const Icon(Icons.cancel_outlined),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _expiresAt(dynamic value) {
    if (value is! num || value <= 0) return '만료일 없음';
    return '${DateFormat('yyyy-MM-dd HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(value.toInt()),
    )} 만료';
  }
}
