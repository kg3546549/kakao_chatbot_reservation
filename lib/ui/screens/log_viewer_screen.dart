import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import 'package:intl/intl.dart';

class LogViewerScreen extends StatelessWidget {
  const LogViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEFEFE),
      appBar: AppBar(title: const Text('시스템 로그')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseService().getLogs(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data!;
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('로그 기록이 없습니다.',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: logs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final log = logs[index];
              final type = log['type'];
              final color = type == '오류'
                  ? Colors.red
                  : (type == '성공' ? const Color(0xFF40916C) : Colors.blue);

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.circle, color: color, size: 10),
                  ),
                  title: Text(log['content'] ?? '',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    DateFormat('MM/dd HH:mm:ss')
                        .format(DateTime.parse(log['timestamp'])),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
