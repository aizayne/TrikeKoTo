import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/ride.dart';
import '../services/location_service.dart';
import 'auth_provider.dart';
import 'rides_provider.dart';

/// Snapshot of the driver's online state, surfaced to the UI.
class PresenceState {
  final bool isOnline;
  final Position? lastPosition;
  final LocationPermissionResult? permission;
  final String? error;

  /// True between tapping "Go online" and the first successful position
  /// fix + Firestore write. Lets the dashboard show a spinner without
  /// flipping prematurely to "online".
  final bool starting;

  const PresenceState({
    this.isOnline = false,
    this.lastPosition,
    this.permission,
    this.error,
    this.starting = false,
  });

  PresenceState copyWith({
    bool? isOnline,
    Position? lastPosition,
    LocationPermissionResult? permission,
    String? error,
    bool? starting,
    bool clearError = false,
  }) {
    return PresenceState(
      isOnline: isOnline ?? this.isOnline,
      lastPosition: lastPosition ?? this.lastPosition,
      permission: permission ?? this.permission,
      error: clearError ? null : (error ?? this.error),
      starting: starting ?? this.starting,
    );
  }
}

final locationServiceProvider = Provider<LocationService>((_) {
  return LocationService();
});

/// Owns the lifecycle of: location stream subscription, wakelock,
/// and the active_drivers/{email} doc. The dashboard widget calls
/// `goOnline()` / `goOffline()` and never touches the SDKs directly.
///
/// Why a long-lived Notifier instead of widget state: the dashboard
/// can be navigated away from (to Profile, History) without the
/// driver actually going offline. State must survive widget rebuilds.
class PresenceNotifier extends Notifier<PresenceState> {
  StreamSubscription<Position>? _positionSub;

  @override
  PresenceState build() {
    // Auto-cleanup when the user signs out from anywhere in the app.
    ref.listen(authStateProvider, (prev, next) {
      final user = next.valueOrNull;
      if (user == null && (state.isOnline || state.starting)) {
        _cleanup();
      }
    });

    // Belt-and-braces: if the provider itself is disposed (e.g. a
    // ProviderScope tear-down during tests) we still leave Firestore
    // in a consistent state by stopping the stream.
    ref.onDispose(_cleanupSync);

    return const PresenceState();
  }

  Future<void> goOnline() async {
    if (state.isOnline || state.starting) return;
    final email = ref.read(authServiceProvider).currentEmail;
    if (email == null) {
      state = state.copyWith(error: 'Sign in first.');
      return;
    }

    state = state.copyWith(starting: true, clearError: true);

    final loc = ref.read(locationServiceProvider);
    final perm = await loc.ensurePermission();
    state = state.copyWith(permission: perm);

    if (perm != LocationPermissionResult.granted) {
      state = state.copyWith(
        starting: false,
        error: _permissionMessage(perm),
      );
      return;
    }

    final db = ref.read(firestoreServiceProvider);

    // Try for an initial fix first — having coords on the very first
    // Firestore write means the matcher can rank this driver
    // immediately instead of waiting for the next stream tick.
    Position? initial;
    try {
      initial = await loc.currentPosition();
    } catch (_) {
      initial = null;
    }

    try {
      await db.setDriverPresence(
        email: email,
        isOnline: true,
        location: initial == null
            ? null
            : GeoCoords(
                lat: initial.latitude,
                lng: initial.longitude,
                accuracy: initial.accuracy,
              ),
      );
    } catch (e) {
      state = state.copyWith(
        starting: false,
        error: 'Could not mark you online: $e',
      );
      return;
    }

    await WakelockPlus.enable();

    _positionSub?.cancel();
    _positionSub = loc.positionStream().listen(
      (p) async {
        state = state.copyWith(lastPosition: p);
        try {
          await db.updateDriverLocation(
            email: email,
            location: GeoCoords(
              lat: p.latitude,
              lng: p.longitude,
              accuracy: p.accuracy,
            ),
          );
        } catch (_) {
          // A single failed write is not fatal — the next tick will
          // retry. Avoid spamming the UI with toasts.
        }
      },
      onError: (e) {
        state = state.copyWith(error: 'Location error: $e');
      },
    );

    state = state.copyWith(
      isOnline: true,
      starting: false,
      lastPosition: initial ?? state.lastPosition,
    );
  }

  Future<void> goOffline() async {
    if (!state.isOnline && !state.starting) return;

    final email = ref.read(authServiceProvider).currentEmail;
    await _stopStreamAndWakelock();

    // If the driver has an in-progress ride, cancel it BEFORE we drop
    // the active_drivers doc — the commuter's screen reacts to status
    // changes via its rideStreamProvider listener and we want them to
    // see "ride cancelled" rather than "driver vanished".
    final activeRide = ref.read(activeRideForDriverProvider).valueOrNull;
    if (activeRide != null) {
      try {
        await ref
            .read(firestoreServiceProvider)
            .cancelRideOnDriverWentOffline(activeRide.id);
      } catch (_) {
        // Best-effort — the ride will time out on the commuter side
        // via the standard 10-minute window anyway.
      }
    }

    if (email != null) {
      try {
        await ref.read(firestoreServiceProvider).setDriverPresence(
              email: email,
              isOnline: false,
            );
      } catch (e) {
        state = state.copyWith(error: 'Could not mark you offline: $e');
      }
    }

    state = state.copyWith(
      isOnline: false,
      starting: false,
      clearError: true,
    );
  }

  Future<void> _cleanup() async {
    final email = ref.read(authServiceProvider).currentEmail;
    await _stopStreamAndWakelock();
    if (email != null) {
      try {
        await ref.read(firestoreServiceProvider).setDriverPresence(
              email: email,
              isOnline: false,
            );
      } catch (_) {/* user is signing out — best-effort */}
    }
    state = const PresenceState();
  }

  /// Sync variant for `onDispose` (no `await`). Cancels the stream and
  /// drops the wakelock; the Firestore write is best-effort and may
  /// not finish if the app is exiting.
  void _cleanupSync() {
    _positionSub?.cancel();
    _positionSub = null;
    WakelockPlus.disable();
  }

  Future<void> _stopStreamAndWakelock() async {
    await _positionSub?.cancel();
    _positionSub = null;
    await WakelockPlus.disable();
  }

  String _permissionMessage(LocationPermissionResult r) {
    switch (r) {
      case LocationPermissionResult.granted:
        return '';
      case LocationPermissionResult.denied:
        return 'Location permission is required to go online.';
      case LocationPermissionResult.deniedForever:
        return 'Location permission was permanently denied. Open Settings to allow it.';
      case LocationPermissionResult.serviceDisabled:
        return 'Location services are off. Turn them on to go online.';
    }
  }
}

final presenceProvider =
    NotifierProvider<PresenceNotifier, PresenceState>(PresenceNotifier.new);
