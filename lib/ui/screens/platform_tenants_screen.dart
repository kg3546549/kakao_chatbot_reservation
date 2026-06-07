import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';

class PlatformTenantsScreen extends StatelessWidget {
  const PlatformTenantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final tenants = FirebaseFirestore.instance
        .collection('tenants')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('전체 가게 관리')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: tenants,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('가게 목록을 불러오지 못했습니다.\n${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final tenant in snapshot.data!.docs)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(tenant.data()['name'] ?? tenant.id),
                    subtitle: Text('ID: ${tenant.id}'),
                    trailing: Switch(
                      value: tenant.data()['status'] == 'active',
                      onChanged: session.busy
                          ? null
                          : (active) => session.updateTenantStatus(
                                tenant.id,
                                active ? 'active' : 'suspended',
                              ),
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
    );
  }
}
