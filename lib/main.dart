import 'dart:ui';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'providers/bot_provider.dart';
import 'providers/session_provider.dart';
import 'models/tenant.dart';
import 'services/push_notification_service.dart';
import 'ui/screens/auth_gate.dart';
import 'package:intl/date_symbol_data_local.dart';

final navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await FirebaseAppCheck.instance.activate(
    androidProvider:
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await FirebaseAppCheck.instance.activate(
    androidProvider:
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
  );
  try {
    await FirebaseAppCheck.instance.getToken(true);
  } catch (error, stack) {
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: 'App Check token refresh failed',
      fatal: false,
    );
  }
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  PushNotificationService.instance.onNotificationTap = (data) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      final session = Provider.of<SessionProvider>(context, listen: false);
      if (session.user == null) return;

      final tenantId = data['tenantId']?.toString();
      if (tenantId == null || tenantId.isEmpty) {
        navigatorKey.currentState?.popUntil((route) => route.isFirst);
        return;
      }

      TenantMembership? targetTenant;
      for (final t in session.tenants) {
        if (t.tenantId == tenantId) {
          targetTenant = t;
          break;
        }
      }

      if (targetTenant != null) {
        if (session.selectedTenant?.tenantId != tenantId ||
            session.mode != AppMode.admin) {
          await session.selectTenant(targetTenant);
          await session.selectMode(AppMode.admin);
        }
        navigatorKey.currentState?.popUntil((route) => route.isFirst);

        final type = data['type']?.toString();
        final nickname = data['nickname']?.toString();
        final itemName = data['itemName']?.toString();
        if (nickname != null && type != null) {
          final actionText = type == 'reservation_created' ? '등록' : '취소/변경';
          final message = '🔔 [$nickname]님의 예약이 $actionText되었습니다. (${itemName ?? ""})';
          
          final scaffoldContext = navigatorKey.currentContext;
          if (scaffoldContext != null && scaffoldContext.mounted) {
            ScaffoldMessenger.of(scaffoldContext).showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });
  };
  await PushNotificationService.instance.initialize();

  // Flutter 프레임워크 오류 → Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  // Dart 비동기 오류 → Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  await initializeDateFormatting('ko_KR', null);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BotProvider()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '카카오톡 예약 관리',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF40916C),
          primary: const Color(0xFF40916C),
          secondary: const Color(0xFF2D6A4F),
          surface: const Color(0xFFF8F9FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F9FA),
          foregroundColor: Color(0xFF1B4332),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF1B4332),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF40916C),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            elevation: 0,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFF40916C).withValues(alpha: 0.1),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF40916C)),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
