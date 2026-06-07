import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import 'home_screen.dart';
import 'admin_home_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, session, _) {
        if (session.initializing) {
          return const _LoadingScreen();
        }
        if (session.user == null) {
          return const LoginScreen();
        }
        if (session.selectedTenant == null) {
          return const TenantSelectionScreen();
        }
        if (session.mode == null) {
          return const ModeSelectionScreen();
        }
        return session.mode == AppMode.bot
            ? const HomeScreen()
            : const AdminHomeScreen();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/logo.png', height: 100),
                  const SizedBox(height: 24),
                  const Text(
                    '카카오톡 예약 관리',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: '이메일',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '비밀번호',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (session.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(session.errorMessage!,
                        style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: session.busy
                        ? null
                        : () => session.signIn(
                              emailController.text,
                              passwordController.text,
                            ),
                    child: const Text('로그인'),
                  ),
                  TextButton(
                    onPressed: session.busy
                        ? null
                        : () => session.register(
                              emailController.text,
                              passwordController.text,
                            ),
                    child: const Text('새 계정 만들기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TenantSelectionScreen extends StatelessWidget {
  const TenantSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('가게 선택'),
        actions: [
          IconButton(
              onPressed: session.signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final tenant in session.tenants)
            Card(
              child: ListTile(
                title: Text(tenant.tenantName),
                subtitle: Text(tenant.role),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => session.selectTenant(tenant),
              ),
            ),
          if (session.tenants.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Text('소속된 가게가 없습니다. 첫 가게를 생성하세요.'),
            ),
          FilledButton.icon(
            onPressed: session.busy ? null : () => _createTenant(context),
            icon: const Icon(Icons.add_business),
            label: const Text('새 가게 만들기'),
          ),
          if (session.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(session.errorMessage!,
                  style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Future<void> _createTenant(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 가게'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '가게 이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('생성'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      await context.read<SessionProvider>().createTenant(name);
    }
  }
}

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final canUseBotMode = ['owner', 'manager', 'botDevice']
        .contains(session.selectedTenant!.role);
    return Scaffold(
      appBar: AppBar(
        title: Text(session.selectedTenant!.tenantName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            session.clearTenant();
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '이 기기에서 사용할 모드를 선택하세요.',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _ModeCard(
            icon: Icons.smart_toy_outlined,
            title: '예약봇 모드',
            description: canUseBotMode
                ? '카카오톡 예약 메시지를 감지하고 자동 응답합니다.'
                : '현재 계정에는 예약봇 실행 권한이 없습니다.',
            onTap: session.busy || !canUseBotMode
                ? null
                : () => session.selectMode(AppMode.bot),
          ),
          _ModeCard(
            icon: Icons.dashboard_outlined,
            title: '관리자 모드',
            description: '예약 현황과 이력, 통계를 확인하고 푸시를 받습니다.',
            onTap:
                session.busy ? null : () => session.selectMode(AppMode.admin),
          ),
          if (session.errorMessage != null)
            Text(session.errorMessage!,
                style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, size: 36, color: const Color(0xFF40916C)),
        title: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(description),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
