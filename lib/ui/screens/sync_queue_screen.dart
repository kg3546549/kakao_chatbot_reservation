import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/cloud_sync_service.dart';

class SyncQueueScreen extends StatefulWidget {
  const SyncQueueScreen({super.key});

  @override
  State<SyncQueueScreen> createState() => _SyncQueueScreenState();
}

class _SyncQueueScreenState extends State<SyncQueueScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _events = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = await CloudSyncService.instance.getSyncQueueEvents();
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  Future<void> _retry(String eventId) async {
    setState(() => _loading = true);
    await CloudSyncService.instance.retrySyncEvent(eventId);
    await _load();
  }

  Future<void> _retryAll() async {
    setState(() => _loading = true);
    await CloudSyncService.instance.retryAllFailedEvents();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final failedCount =
        _events.where((event) => event['status'] == 'failed').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('서버 동기화 상태'),
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
                if (failedCount > 0)
                  FilledButton.icon(
                    onPressed: _retryAll,
                    icon: const Icon(Icons.sync),
                    label: Text('실패 이벤트 전체 재시도 ($failedCount건)'),
                  ),
                if (_events.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: Text('대기 중인 동기화 이벤트가 없습니다.')),
                    ),
                  ),
                for (final event in _events) _eventCard(event),
              ],
            ),
    );
  }

  Widget _eventCard(Map<String, dynamic> event) {
    final payload = _payload(event['payload']);
    final failed = event['status'] == 'failed';
    return Card(
      child: ExpansionTile(
        leading: Icon(
          failed ? Icons.error_outline : Icons.schedule_outlined,
          color: failed ? Colors.red : Colors.orange,
        ),
        title: Text(
            '${payload['type'] ?? 'event'} · ${payload['nickname'] ?? ''}'),
        subtitle: Text(
          '시도 ${event['attempts'] ?? 0}회'
          '${event['next_attempt_at'] == null ? '' : ' · 다음 ${event['next_attempt_at']}'}',
        ),
        trailing: failed
            ? IconButton(
                tooltip: '즉시 재시도',
                onPressed: () => _retry(event['event_id'].toString()),
                icon: const Icon(Icons.sync),
              )
            : null,
        children: [
          ListTile(
            title: const Text('이벤트 ID'),
            subtitle: Text(event['event_id']?.toString() ?? ''),
          ),
          if (event['last_error'] != null)
            ListTile(
              title: const Text('최근 오류'),
              subtitle: Text(event['last_error'].toString()),
            ),
        ],
      ),
    );
  }

  Map<String, dynamic> _payload(dynamic rawPayload) {
    try {
      return Map<String, dynamic>.from(
          jsonDecode(rawPayload.toString()) as Map);
    } catch (_) {
      return const {};
    }
  }
}
