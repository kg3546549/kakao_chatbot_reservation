import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';

class TenantDevicesScreen extends StatelessWidget {
  const TenantDevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final tenant = session.selectedTenant!;
    final devices = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant.tenantId)
        .collection('devices')
        .orderBy('lastSeenAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('연결 기기 관리')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: devices,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('기기를 불러오지 못했습니다.\n${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final device in snapshot.data!.docs)
                Card(
                  child: ListTile(
                    leading: Icon(
                      device.data()['mode'] == 'bot'
                          ? Icons.smart_toy_outlined
                          : Icons.phone_android,
                    ),
                    title: Text(
                      device.data()['mode'] == 'bot' ? '예약봇 기기' : '관리자 기기',
                    ),
                    subtitle: Text(
                      '${device.data()['status'] ?? 'unknown'} · ${device.id}',
                    ),
                    trailing: device.data()['mode'] == 'bot' &&
                            device.data()['status'] == 'active'
                        ? IconButton(
                            tooltip: '예약봇 연결 해제',
                            onPressed: session.busy
                                ? null
                                : () => session.releaseBotDevice(device.id),
                            icon: const Icon(Icons.link_off),
                          )
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
