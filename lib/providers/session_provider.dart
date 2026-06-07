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
        .listen((snapshot) {
      tenants = snapshot.docs
          .map((doc) => TenantMembership.fromMap(doc.data()))
          .toList();
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

  Future<void> signOut() async {
    await _deactivateCurrentDevice();
    await _setNativeBotMode(false);
    await _auth.signOut();
  }

  Future<void> createTenant(String name) async {
    await _run(() async {
      await _functions
          .httpsCallable('createTenant')
          .call({'name': name.trim()});
    });
  }

  void selectTenant(TenantMembership tenant) {
    selectedTenant = tenant;
    mode = null;
    notifyListeners();
  }

  void clearTenant() {
    selectedTenant = null;
    mode = null;
    CloudSyncService.instance.clear();
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
    });
  }

  Future<void> leaveMode() async {
    await _deactivateCurrentDevice();
    await _setNativeBotMode(false);
    mode = null;
    CloudSyncService.instance.clear();
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
