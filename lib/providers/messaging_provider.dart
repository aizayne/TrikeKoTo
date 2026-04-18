import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/messaging_service.dart';
import 'auth_provider.dart';

final firebaseMessagingProvider = Provider<FirebaseMessaging>((_) {
  return FirebaseMessaging.instance;
});

final messagingServiceProvider = Provider<MessagingService>((ref) {
  return MessagingService(ref.watch(firebaseMessagingProvider));
});

/// Side-effect notifier that keeps `active_drivers/{email}.fcmToken`
/// in sync with the Firebase Messaging registration. Lifecycle:
///
///   * On sign-in   → request permission, fetch token, write it.
///                    Subscribe to `onTokenRefresh` and forward future
///                    rotations to Firestore so the server can keep
///                    targeting this device.
///   * On sign-out  → cancel the refresh subscription. We don't bother
///                    deleting the stale token from Firestore — the
///                    presence doc will already be flipped to
///                    `isOnline: false` by [PresenceNotifier], and a
///                    Cloud Function targeting the token will silently
///                    no-op when the user is offline.
///
/// Errors anywhere in this flow are swallowed: push notifications are
/// a nice-to-have, not load-bearing. The driver dashboard still works
/// when FCM is denied, unsupported, or simply offline.
class PushRegistrationNotifier extends Notifier<void> {
  StreamSubscription<String>? _refreshSub;

  @override
  void build() {
    ref.listen(authStateProvider, (prev, next) {
      final email = next.valueOrNull?.email;
      if (email != null) {
        _register(email);
      } else {
        _stop();
      }
    }, fireImmediately: true);
    ref.onDispose(_stop);
  }

  Future<void> _register(String email) async {
    final svc = ref.read(messagingServiceProvider);
    final db = ref.read(firestoreServiceProvider);

    bool granted = false;
    try {
      granted = await svc.requestPermission();
    } catch (_) {
      return;
    }
    if (!granted) return;

    String? token;
    try {
      token = await svc.getToken();
    } catch (_) {
      token = null;
    }

    if (token != null) {
      try {
        await db.updateFcmToken(email: email, token: token);
      } catch (_) {/* best-effort */}
    }

    _refreshSub?.cancel();
    _refreshSub = svc.onTokenRefresh.listen((t) async {
      try {
        await db.updateFcmToken(email: email, token: t);
      } catch (_) {/* best-effort */}
    });
  }

  void _stop() {
    _refreshSub?.cancel();
    _refreshSub = null;
  }
}

/// Mounting this provider is what *starts* the push registration flow.
/// `TrikeKoToApp` watches it once at the root so the lifecycle follows
/// the app lifecycle.
final pushRegistrationProvider =
    NotifierProvider<PushRegistrationNotifier, void>(
  PushRegistrationNotifier.new,
);
