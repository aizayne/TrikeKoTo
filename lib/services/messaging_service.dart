import 'package:firebase_messaging/firebase_messaging.dart';

/// Thin wrapper around `FirebaseMessaging` so the rest of the app can
/// treat push notifications as one boring side-effect: ask permission,
/// fetch a token, watch for refreshes.
///
/// We deliberately don't ship `flutter_local_notifications` — when the
/// driver is in the foreground they're already on the dashboard which
/// auto-updates from the Firestore stream, so a banner would just be
/// duplicate noise. Background / terminated delivery is handled by the
/// system, which is what FCM does out of the box on Android & iOS.
class MessagingService {
  MessagingService(this._messaging);

  final FirebaseMessaging _messaging;

  /// Asks the OS for notification permission. Returns true when the
  /// user grants either full or provisional authorization (provisional
  /// is iOS-only and still surfaces silent notifications). Calling
  /// this when permission has already been granted is a no-op.
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    final s = settings.authorizationStatus;
    return s == AuthorizationStatus.authorized ||
        s == AuthorizationStatus.provisional;
  }

  /// Returns the current FCM registration token, or null when push is
  /// unsupported (e.g. running on web without a VAPID key configured).
  Future<String?> getToken() => _messaging.getToken();

  /// Stream that fires whenever FCM rotates the registration token.
  /// Subscribers should write the new token back to Firestore so the
  /// server keeps targeting the right device.
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// Foreground messages — useful for in-app toasts. Out of scope for
  /// the current build, but exposed so a future iteration can show a
  /// SnackBar without reaching for the SDK.
  Stream<RemoteMessage> get onForegroundMessage => FirebaseMessaging.onMessage;
}
