import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/driver.dart';
import '../models/ride.dart';
import '../services/matching_service.dart';
import 'auth_provider.dart';
import 'presence_provider.dart';

/// Live snapshot of a single ride doc — used by the commuter screen.
/// autoDispose so the listener tears down when navigating away from
/// the booking flow.
final rideStreamProvider =
    StreamProvider.autoDispose.family<Ride, String>((ref, rideId) {
  return ref.watch(firestoreServiceProvider).watchRide(rideId);
});

/// Stream of every ride currently in `searching` status. The matcher
/// then narrows this down to rides actually offered to *this* driver.
final searchingRidesProvider = StreamProvider<List<Ride>>((ref) {
  return ref.watch(firestoreServiceProvider).watchSearchingRides();
});

/// Stream of online drivers (presence collection). Used as the input
/// to the deterministic ranking — every driver sees the same list and
/// computes the same offer order independently.
final onlineDriversProvider = StreamProvider<List<OnlineDriver>>((ref) {
  return ref.watch(firestoreServiceProvider).watchOnlineDrivers().map(
    (rows) {
      final out = <OnlineDriver>[];
      for (final r in rows) {
        try {
          out.add(OnlineDriver.fromActiveDoc(r));
        } catch (_) {
          // Tolerate stale/half-written presence docs (no location yet).
        }
      }
      return out;
    },
  );
});

/// Emits an incrementing counter every 5 seconds. The matcher reads
/// this so the offer window widens on schedule even when no Firestore
/// snapshot arrives. Mirrors the `filterTick` interval in the React
/// reference.
final filterTickProvider = StreamProvider<int>((ref) {
  final controller = StreamController<int>();
  var n = 0;
  controller.add(n);
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    controller.add(++n);
  });
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The current driver's accepted-but-not-yet-completed ride, if any.
/// Returns `null` when offline or when no ride has been accepted.
final activeRideForDriverProvider = StreamProvider<Ride?>((ref) {
  final email = ref.watch(authServiceProvider).currentEmail;
  if (email == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchActiveRideFor(email);
});

/// Final selector: rides this specific driver is currently being
/// offered, sorted in priority order (top-of-rank first, then by
/// distance, then newest first).
///
/// Returns an empty list when:
///   - the driver is offline
///   - the driver already has an active ride (never offer a second)
///   - no ride is in offer range
final incomingRidesProvider = Provider<List<OfferedRide>>((ref) {
  final presence = ref.watch(presenceProvider);
  if (!presence.isOnline) return const [];

  final activeRide = ref.watch(activeRideForDriverProvider).valueOrNull;
  if (activeRide != null) return const [];

  final email = ref.watch(authServiceProvider).currentEmail;
  if (email == null) return const [];

  final rides = ref.watch(searchingRidesProvider).valueOrNull ?? const [];
  final peers = ref.watch(onlineDriversProvider).valueOrNull ?? const [];

  // Tick subscription — we read the value but only to register a
  // dependency; the actual time we use is `DateTime.now()` so the
  // computation is monotonic with wall-clock and unaffected by
  // missed ticks.
  ref.watch(filterTickProvider);
  final now = DateTime.now();

  final pos = presence.lastPosition;
  final selfCoords = pos == null
      ? null
      : (lat: pos.latitude, lng: pos.longitude);

  final eligible =
      rides.where((r) => isRideEligibleForMatching(r, now)).toList();

  final scored = <OfferedRide>[];
  for (final r in eligible) {
    final s = rankRideForDriver(
      ride: r,
      selfEmail: email,
      peers: peers,
      selfCoords: selfCoords,
      now: now,
    );
    // Proximity gate, with the same React-style fallback: when
    // distance can't be computed at all (no self coords or no
    // pickupCoords) we surface the ride rather than hide it.
    if (s.distanceKm == null) {
      scored.add(s);
      continue;
    }
    if (s.distanceKm! > AppConstants.proximityKm) continue;
    if (!s.offered) continue;
    scored.add(s);
  }

  scored.sort((a, b) {
    final ra = a.myRank < 0 ? 1 << 30 : a.myRank;
    final rb = b.myRank < 0 ? 1 << 30 : b.myRank;
    if (ra != rb) return ra.compareTo(rb);
    if (a.distanceKm != null && b.distanceKm != null) {
      return a.distanceKm!.compareTo(b.distanceKm!);
    }
    final ta = a.ride.createdAt?.millisecondsSinceEpoch ?? 0;
    final tb = b.ride.createdAt?.millisecondsSinceEpoch ?? 0;
    return tb.compareTo(ta);
  });

  return scored;
});

/// Live `location` map of one specific driver, mirrored from
/// `active_drivers/{email}`. autoDispose so the listener tears down
/// the moment the commuter leaves the accepted-phase screen.
///
/// Emits null while the doc is missing, the driver is offline, or no
/// GPS fix exists yet — the UI uses that to show a "waiting for GPS"
/// placeholder instead of the map.
final driverLiveLocationProvider =
    StreamProvider.autoDispose.family<GeoCoords?, String>((ref, driverEmail) {
  return ref.watch(firestoreServiceProvider).watchDriverLocation(driverEmail);
});

/// One-shot fetch of the driver profile, for the commuter's "your
/// driver" card. autoDispose so leaving the screen drops the cache.
/// Returns null if the doc doesn't exist (rule-blocked or deleted).
final driverProfileProvider =
    FutureProvider.autoDispose.family<Driver?, String>((ref, driverEmail) {
  return ref.watch(firestoreServiceProvider).getDriver(driverEmail);
});

/// Upcoming scheduled rides that are NOT yet eligible for matching
/// (their pickup is more than [AppConstants.scheduledLeadTime] away).
/// Surfaced as a glance-ahead list on the dashboard.
final upcomingScheduledRidesProvider = Provider<List<Ride>>((ref) {
  ref.watch(filterTickProvider);
  final now = DateTime.now();
  final rides = ref.watch(searchingRidesProvider).valueOrNull ?? const [];
  final upcoming = rides.where((r) {
    final s = r.scheduledFor;
    if (s == null) return false;
    return s.difference(now) > AppConstants.scheduledLeadTime;
  }).toList()
    ..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!));
  return upcoming.take(3).toList();
});
