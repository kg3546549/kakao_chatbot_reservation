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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _deviceSubscription;

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
    await _deviceSubscription?.cancel();

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
      String? tenantLoadWarning;
      for (final membership in snapshot.docs) {
        final membershipData = membership.data();
        final tenantId = (membershipData['tenantId'] ?? membership.id).toString();
        try {
          final tenant = await _firestore.collection('tenants').doc(tenantId).get();
          if (tenant.data()?['status'] == 'active') {
            activeTenants.add(
              TenantMembership.fromMap({
                ...membershipData,
                'tenantId': tenantId,
                'tenantName':
                    membershipData['tenantName'] ?? tenant.data()?['name'],
              }),
            );
          }
        } on FirebaseException catch (error) {
          debugPrint('Skipping inaccessible tenant $tenantId: $error');
          tenantLoadWarning = '접근 권한이 없는 가게가 있어 목록에서 제외했습니다.';
        }
      }
      tenants = activeTenants;
      errorMessage = tenantLoadWarning;
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
    final validationError = _validateCredentials(email, password);
    if (validationError != null) {
      _setError(validationError);
      return;
    }
    await _run(() => _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ));
  }

  Future<void> register(String email, String password) async {
    final validationError = _validateCredentials(email, password);
    if (validationError != null) {
      _setError(validationError);
      return;
    }
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
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('device_id');
      deviceId ??= '${user!.uid}-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString('device_id', deviceId);

      String token = '';
      if (nextMode == AppMode.admin) {
        await _messaging.requestPermission();
        token = await _messaging.getToken() ?? '';
      }

      mode = nextMode;
      try {
        await _registerCurrentDevice(
          deviceId: deviceId,
          token: token,
        );
      } catch (_) {
        mode = null;
        await _setNativeBotMode(false);
        rethrow;
      }
      await CloudSyncService.instance.configure(
        tenantId: tenant.tenantId,
        deviceId: deviceId,
        botMode: nextMode == AppMode.bot,
      );
      await _setNativeBotMode(nextMode == AppMode.bot);
      if (nextMode == AppMode.bot) {
        _watchBotDevice(tenant.tenantId, deviceId);
      }
      await prefs.setString('selected_mode', nextMode.name);
    });
  }

  Future<void> leaveMode() async {
    await _deactivateCurrentDevice();
    await _setNativeBotMode(false);
    await _deviceSubscription?.cancel();
    _deviceSubscription = null;
    mode = null;
    CloudSyncService.instance.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_mode');
    notifyListeners();
  }

  Future<void> createAdminReservation({
    required String itemId,
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
        'itemId': itemId,
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

  Future<void> updateAdminReservation({
    required Map<String, dynamic> reservation,
    required String itemId,
    required String itemName,
    required String nickname,
    required String roomName,
  }) async {
    final tenant = selectedTenant;
    if (tenant == null) return;
    final reservationId = (reservation['reservationId'] ?? '').toString();
    if (reservationId.isEmpty) return;
    await _run(() async {
      await _functions.httpsCallable('createReservationEvent').call({
        'tenantId': tenant.tenantId,
        'eventId':
            'event-update-${user!.uid}-${DateTime.now().microsecondsSinceEpoch}',
        'reservationId': reservationId,
        'type': 'updated',
        'itemId': itemId,
        'itemName': itemName,
        'nickname': nickname.trim(),
        'roomName': roomName.trim(),
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

  Future<String?> createTenantInvite({
    required String email,
    required String role,
  }) async {
    final tenant = selectedTenant;
    if (tenant == null) return null;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _functions.httpsCallable('createTenantInvite').call({
        'tenantId': tenant.tenantId,
        'email': email.trim(),
        'role': role,
      });
      return Map<String, dynamic>.from(result.data as Map)['inviteId']
          ?.toString();
    } on FirebaseFunctionsException catch (error) {
      errorMessage = error.message ?? '초대 생성에 실패했습니다.';
      return null;
    } catch (error) {
      errorMessage = error.toString();
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> acceptTenantInvite(String inviteId) async {
    await _run(() async {
      await _functions
          .httpsCallable('acceptTenantInvite')
          .call({'inviteId': inviteId.trim()});
    });
  }

  Future<List<Map<String, dynamic>>> listTenantInvites() async {
    final tenant = selectedTenant;
    if (tenant == null) return [];
    final result = await _functions
        .httpsCallable('listTenantInvites')
        .call({'tenantId': tenant.tenantId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['invites'] as List? ?? const [])
        .map((invite) => Map<String, dynamic>.from(invite as Map))
        .toList();
  }

  Future<void> revokeTenantInvite(String inviteId) async {
    final tenant = selectedTenant;
    if (tenant == null) return;
    await _run(() async {
      await _functions.httpsCallable('revokeTenantInvite').call({
        'tenantId': tenant.tenantId,
        'inviteId': inviteId,
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

  Future<void> releaseBotDevice(String deviceId) async {
    final tenant = selectedTenant;
    if (tenant == null) return;
    await _run(() async {
      await _functions.httpsCallable('releaseBotDevice').call({
        'tenantId': tenant.tenantId,
        'deviceId': deviceId,
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
      try {
        await _registerCurrentDevice(deviceId: deviceId);
      } catch (_) {
        mode = null;
        selectedTenant = null;
        await _clearSavedSession();
        await _setNativeBotMode(false);
        return;
      }
      await CloudSyncService.instance.configure(
        tenantId: tenant.tenantId,
        deviceId: deviceId,
        botMode: restoredMode == AppMode.bot,
      );
      await _setNativeBotMode(restoredMode == AppMode.bot);
      if (restoredMode == AppMode.bot) {
        _watchBotDevice(tenant.tenantId, deviceId);
      }
    }
  }

  void _watchBotDevice(String tenantId, String deviceId) {
    _deviceSubscription?.cancel();
    _deviceSubscription = _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('devices')
        .doc(deviceId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists || snapshot.data()?['status'] != 'active') {
        await _disableBotModeLocally();
      }
    }, onError: (_) => _disableBotModeLocally());
  }

  Future<void> _disableBotModeLocally() async {
    await _setNativeBotMode(false);
    mode = null;
    CloudSyncService.instance.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_mode');
    notifyListeners();
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
      errorMessage = _firebaseAuthMessage(error);
    } on FirebaseFunctionsException catch (error) {
      errorMessage = error.message ?? '서버 요청에 실패했습니다.';
    } on PlatformException catch (error) {
      errorMessage = error.message ?? '요청을 처리하지 못했습니다.';
    } catch (error) {
      errorMessage = '요청을 처리하지 못했습니다. 잠시 후 다시 시도하세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _firebaseAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return '올바른 이메일 주소를 입력하세요.';
      case 'weak-password':
        return '더 안전한 비밀번호를 입력하세요.';
      case 'email-already-in-use':
        return '이미 가입된 이메일입니다.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 올바르지 않습니다.';
      case 'network-request-failed':
        return '네트워크 연결을 확인하세요.';
      default:
        if ((error.message ?? '')
            .contains('Firebase App Check Token is invalid')) {
          return '앱 인증 정보를 갱신하지 못했습니다. 앱을 다시 실행해 주세요.';
        }
        return '로그인 처리에 실패했습니다.';
    }
  }

  String? _validateCredentials(String email, String password) {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) return '이메일을 입력하세요.';
    if (!normalizedEmail.contains('@')) return '올바른 이메일 주소를 입력하세요.';
    if (password.isEmpty) return '비밀번호를 입력하세요.';
    if (password.length < 6) return '비밀번호는 6자 이상 입력하세요.';
    return null;
  }

  void _setError(String message) {
    errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _tenantSubscription?.cancel();
    _tokenSubscription?.cancel();
    _deviceSubscription?.cancel();
    super.dispose();
  }
}
