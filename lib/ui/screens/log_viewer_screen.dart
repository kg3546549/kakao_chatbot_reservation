import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import 'package:intl/intl.dart';

class LogViewerScreen extends StatelessWidget {
  const LogViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('시스템 로그')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseService().getLogs(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final logs = snapshot.data!;
          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final log = logs[index];
              final type = log['type'];
              final color = type == '오류' ? Colors.red : (type == '성공' ? Colors.green : Colors.blue);
              
              return ListTile(
                leading: Icon(Icons.circle, color: color, size: 12),
                title: Text(log['content'] ?? ''),
                subtitle: Text(DateFormat('HH:mm:ss').format(DateTime.parse(log['timestamp']))),
              );
            },
          );
        },
      ),
    );
  }
}
