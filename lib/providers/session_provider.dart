import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tenant.dart';
import '../services/cloud_sync_service.dart';

enum AppMode { bot, admin }

class SessionProvider with ChangeNotifier {
  static const _channel = MethodChannel('com.geon.kakao_bot/notification');

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tenantSubscription;
  StreamSubscription<String>? _tokenSubscription;

  User? user;
  List<TenantMembership> tenants = [];
  TenantMembership? selectedTenant;
  AppMode? mode;
  bool platformAdmin = false;
  bool initializing = true;
  bool busy = false;
  String? errorMessage;

  SessionProvider() {
    _authSubscription = _auth.authStateChanges().listen(_handleAuthChanged);
    _tokenSubscription = _messaging.onTokenRefresh.listen((_) {
      if (mode == AppMode.admin) {
        _registerCurrentDevice();
      }
    });
  }

  Future<void> _handleAuthChanged(User? nextUser) async {
    user = nextUser;
    selectedTenant = null;
    mode = null;
    platformAdmin = false;
    tenants = [];
    await _tenantSubscription?.cancel();

    if (nextUser == null) {
      initializing = false;
      await _setNativeBotMode(false);
      notifyListeners();
      return;
    }
    platformAdmin =
        (await nextUser.getIdTokenResult()).claims?['platformAdmin'] == true;

    try {
      await _firestore.collection('users').doc(nextUser.uid).set({
        'email': nextUser.email,
        'displayName': nextUser.displayName,
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to update user profile: $error');
    }

    _tenantSubscription = _firestore
        .collection('users')
        .doc(nextUser.uid)
        .collection('tenantMemberships')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snapshot) async {
      final activeTenants = <TenantMembership>[];
      for (final membership in snapshot.docs) {
        final tenantId = membership.data()['tenantId'] ?? membership.id;
        final tenant =
            await _firestore.collection('tenants').doc(tenantId).get();
        if (tenant.data()?['status'] == 'active') {
          activeTenants.add(TenantMembership.fromMap(membership.data()));
        }
      }
      tenants = activeTenants;
      await _restoreLastSession();
      initializing = false;
      notifyListeners();
    }, onError: (Object error) {
      errorMessage = '가게 목록을 불러오지 못했습니다: $error';
      initializing = false;
      notifyListeners();
    });
  }

  Future<void> signIn(String email, String password) async {
    await _run(() => _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ));
  }

  Future<void> register(String email, String password) async {
    await _run(() => _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ));
  }

  Future<void> sendPasswordReset(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      errorMessage = '비밀번호를 재설정할 이메일을 입력하세요.';
      notifyListeners();
      return;
    }
    await _run(() => _auth.sendPasswordResetEmail(email: normalizedEmail));
  }

  Future<void> signOut() async {
    await _deactivateCurrentDevice();
    await _setNativeBotMode(false);
    await _clearSavedSession();
    await _auth.signOut();
  }

  Future<void> createTenant(String name) async {
    await _run(() async {
      await _functions
          .httpsCallable('createTenant')
          .call({'name': name.trim()});
    });
  }

  Future<void> selectTenant(TenantMembership tenant) async {
    selectedTenant = tenant;
    mode = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_tenant_id', tenant.tenantId);
    notifyListeners();
  }

  void clearTenant() {
    selectedTenant = null;
    mode = null;
    CloudSyncService.instance.clear();
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('selected_tenant_id');
      prefs.remove('selected_mode');
    });
    notifyListeners();
  }

  Future<void> selectMode(AppMode nextMode) async {
    final tenant = selectedTenant;
    if (tenant == null) return;

    await _run(() async {
      mode = nextMode;
      await _setNativeBotMode(nextMode == AppMode.bot);

      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('device_id');
      deviceId ??= '${user!.uid}-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString('device_id', deviceId);
      CloudSyncService.instance.configure(
        tenantId: tenant.tenantId,
        deviceId: deviceId,
      );

      String token = '';
      if (nextMode == AppMode.admin) {
        await _messaging.requestPermission();
        token = await _messaging.getToken() ?? '';
      }

      await _registerCurrentDevice(
        deviceId: deviceId,
        token: token,
      );
      await prefs.setString('selected_mode', nextMode.name);
    });
  }

  Future<void> leaveMode() async {
    await _deactivateCurrentDevice();
    await _setNativeBotMode(false);
    mode = null;
    CloudSyncService.instance.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_mode');
    notifyListeners();
  }

  Future<void> createAdminReservation({
    required String itemName,
    required String nickname,
    required String roomName,
  }) async {
    final tenant = selectedTenant;
    if (tenant == null) return;
    final now = DateTime.now();
    final id = '${user!.uid}-${now.microsecondsSinceEpoch}';
    await _run(() async {
      await _functions.httpsCallable('createReservationEvent').call({
        'tenantId': tenant.tenantId,
        'eventId': 'event-$id',
        'reservationId': 'admin-$id',
        'type': 'created',
        'itemId': itemName.trim(),
        'itemName': itemName.trim(),
        'nickname': nickname.trim(),
        'roomName': roomName.trim(),
        'businessDate': DateFormat('yyyy-MM-dd').format(now),
        'sourceDeviceId': 'admin',
      });
    });
  }

  Future<void> cancelAdminReservation(Map<String, dynamic> reservation) async {
    final tenant = selectedTenant;
    if (tenant == null) return;
    final reservationId = (reservation['reservationId'] ?? '').toString();
    if (reservationId.isEmpty) return;
    final eventId =
        'event-cancel-${user!.uid}-${DateTime.now().microsecondsSinceEpoch}';
    await _run(() async {
      await _functions.httpsCallable('createReservationEvent').call({
        'tenantId': tenant.tenantId,
        'eventId': eventId,
        'reservationId': reservationId,
        'type': 'cancelled',
        'itemId': (reservation['itemId'] ?? '').toString(),
        'itemName': (reservation['itemName'] ?? '').toString(),
        'nickname': (reservation['nickname'] ?? '').toString(),
        'roomName': (reservation['roomName'] ?? '').toString(),
        'businessDate': (reservation['businessDate'] ?? '').toString(),
        'sourceDeviceId': 'admin',
      });
    });
  }

  Future<void> addTenantMember({
    required String email,
    required String role,
  }) async {
    final tenant = selectedTenant;
    if (tenant == null) return;
    await _run(() async {
      await _functions.httpsCallable('addTenantMember').call({
        'tenantId': tenant.tenantId,
        'email': email.trim(),
        'role': role,
      });
    });
  }

  Future<void> removeTenantMember(String memberUid) async {
    final tenant = selectedTenant;
    if (tenant == null) return;
    await _run(() async {
      await _functions.httpsCallable('removeTenantMember').call({
        'tenantId': tenant.tenantId,
        'memberUid': memberUid,
      });
    });
  }

  Future<void> updateTenantStatus(String tenantId, String status) async {
    await _run(() async {
      await _functions.httpsCallable('updateTenantStatus').call({
        'tenantId': tenantId,
        'status': status,
      });
    });
  }

  Future<void> bootstrapPlatformAdmin() async {
    await _run(() async {
      await _functions.httpsCallable('bootstrapPlatformAdmin').call();
      await user?.getIdToken(true);
      platformAdmin =
          (await user?.getIdTokenResult(true))?.claims?['platformAdmin'] ==
              true;
    });
  }

  Future<void> _setNativeBotMode(bool enabled) async {
    try {
      await _channel.invokeMethod('setBotMode', {'enabled': enabled});
    } on PlatformException catch (error) {
      debugPrint('Failed to switch native bot mode: $error');
    }
  }

  Future<void> _restoreLastSession() async {
    if (selectedTenant != null || mode != null || user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final tenantId = prefs.getString('selected_tenant_id');
    final modeName = prefs.getString('selected_mode');
    if (tenantId == null || modeName == null) return;

    TenantMembership? tenant;
    for (final candidate in tenants) {
      if (candidate.tenantId == tenantId) {
        tenant = candidate;
        break;
      }
    }
    if (tenant == null) {
      await _clearSavedSession();
      await _setNativeBotMode(false);
      return;
    }

    final restoredMode = modeName == AppMode.bot.name
        ? AppMode.bot
        : modeName == AppMode.admin.name
            ? AppMode.admin
            : null;
    if (restoredMode == null ||
        (restoredMode == AppMode.bot &&
            !['owner', 'manager', 'botDevice'].contains(tenant.role))) {
      await _clearSavedSession();
      await _setNativeBotMode(false);
      return;
    }

    selectedTenant = tenant;
    mode = restoredMode;
    final deviceId = prefs.getString('device_id');
    if (deviceId != null) {
      CloudSyncService.instance.configure(
        tenantId: tenant.tenantId,
        deviceId: deviceId,
      );
      await _setNativeBotMode(restoredMode == AppMode.bot);
      await _registerCurrentDevice(deviceId: deviceId);
    }
  }

  Future<void> _clearSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_tenant_id');
    await prefs.remove('selected_mode');
  }

  Future<void> _registerCurrentDevice({
    String? deviceId,
    String? token,
  }) async {
    final tenant = selectedTenant;
    final selectedMode = mode;
    if (tenant == null || selectedMode == null || user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final resolvedDeviceId = deviceId ?? prefs.getString('device_id');
    if (resolvedDeviceId == null) return;

    final resolvedToken = selectedMode == AppMode.admin
        ? token ?? await _messaging.getToken() ?? ''
        : '';
    await _functions.httpsCallable('registerDevice').call({
      'tenantId': tenant.tenantId,
      'deviceId': resolvedDeviceId,
      'mode': selectedMode.name,
      'fcmToken': resolvedToken,
    });
  }

  Future<void> _deactivateCurrentDevice() async {
    final tenant = selectedTenant;
    if (tenant == null || user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    if (deviceId == null) return;

    try {
      await _functions.httpsCallable('unregisterDevice').call({
        'tenantId': tenant.tenantId,
        'deviceId': deviceId,
      });
    } catch (error) {
      debugPrint('Failed to unregister device: $error');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      errorMessage = error.message ?? '로그인 처리에 실패했습니다.';
    } on FirebaseFunctionsException catch (error) {
      errorMessage = error.message ?? '서버 요청에 실패했습니다.';
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _tenantSubscription?.cancel();
    _tokenSubscription?.cancel();
    super.dispose();
  }
}
