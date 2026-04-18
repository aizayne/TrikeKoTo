import '../core/constants.dart';
import '../core/utils/email.dart';
import '../core/utils/haversine.dart';
import '../models/ride.dart';

/// One online driver as seen by the matcher. We deliberately keep this
/// flat (not the full active_drivers doc) so the same shape can be
/// synthesised in-memory for the local self-entry — the React reference
/// does the same trick to avoid stale Firestore reads of own location.
class OnlineDriver {
  final String email;
  final double lat;
  final double lng;

  const OnlineDriver({
    required this.email,
    required this.lat,
    required this.lng,
  });

  factory OnlineDriver.fromActiveDoc(Map<String, dynamic> doc) {
    final loc = doc['location'];
    if (loc is! Map) {
      throw const FormatException('active_drivers doc missing location');
    }
    final m = Map<String, dynamic>.from(loc);
    return OnlineDriver(
      email: normalizeEmail((doc['email'] as String?) ?? ''),
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
    );
  }
}

/// One ride as offered to the current driver, after running the greedy
/// matcher. `myRank` is 0-based: 0 means "you are the closest". `-1`
/// means out of proximity (or pickupCoords missing — degraded mode).
class OfferedRide {
  final Ride ride;
  final double? distanceKm;
  final int myRank;
  final int offerDepth;
  final int totalRanked;
  final bool offered;
  final bool isSolo;

  const OfferedRide({
    required this.ride,
    required this.distanceKm,
    required this.myRank,
    required this.offerDepth,
    required this.totalRanked,
    required this.offered,
    required this.isSolo,
  });
}

/// Pure ranking function — given a ride and the current set of online
/// drivers, returns the deterministic priority list of driver emails
/// in offer order: closest first, ties broken alphabetically by email.
///
/// Drivers outside [AppConstants.proximityKm] are excluded entirely.
/// Returns an empty list if the ride has no pickupCoords (the caller
/// then falls into degraded "show to everyone" mode).
List<String> rankDriversForRide(Ride ride, List<OnlineDriver> onlineDrivers) {
  final pc = ride.pickupCoords;
  if (pc == null) return const [];
  final ranked = <_RankedDriver>[];
  for (final d in onlineDrivers) {
    if (d.email.isEmpty) continue;
    final km = haversineKm(d.lat, d.lng, pc.lat, pc.lng);
    if (km > AppConstants.proximityKm) continue;
    ranked.add(_RankedDriver(d.email, km));
  }
  ranked.sort((a, b) {
    final c = a.km.compareTo(b.km);
    if (c != 0) return c;
    return a.email.compareTo(b.email);
  });
  return ranked.map((r) => r.email).toList(growable: false);
}

class _RankedDriver {
  final String email;
  final double km;
  const _RankedDriver(this.email, this.km);
}

/// How many drivers in the deterministic ranking are currently being
/// offered the ride. The window widens by one driver per
/// [AppConstants.offerExpand], capped at [AppConstants.maxOfferDepth].
///
/// 0–15s   → 1 driver
/// 15–30s  → 2 drivers
/// …
/// 135s+   → 10 drivers (cap)
int currentOfferDepth(Ride ride, DateTime now) {
  final created = ride.createdAt ?? now;
  final ageMs = now.difference(created).inMilliseconds;
  final ticks = ageMs < 0 ? 0 : ageMs ~/ AppConstants.offerExpand.inMilliseconds;
  final depth = ticks + 1;
  if (depth > AppConstants.maxOfferDepth) return AppConstants.maxOfferDepth;
  return depth;
}

/// True if the ride is still eligible to be considered for matching.
/// Mirrors the React filter: scheduled rides only enter the queue once
/// pickup is within [AppConstants.scheduledLeadTime]; immediate rides
/// drop off after [AppConstants.rideQueueWindow].
bool isRideEligibleForMatching(Ride ride, DateTime now) {
  if (ride.status != RideStatus.searching) return false;
  final scheduled = ride.scheduledFor;
  if (scheduled != null) {
    final until = scheduled.difference(now);
    return until <= AppConstants.scheduledLeadTime;
  }
  final created = ride.createdAt;
  if (created == null) return true; // server timestamp not yet committed
  return now.difference(created) <= AppConstants.rideQueueWindow;
}

/// Combines [rankDriversForRide], [currentOfferDepth], and the proximity
/// fallback into one call. This is the single entry point the dashboard
/// provider uses per ride.
///
/// `selfCoords` is the live GPS for this driver — we splice it into the
/// peer set even when active_drivers is stale, so the ranking always
/// reflects the freshest possible position for self.
OfferedRide rankRideForDriver({
  required Ride ride,
  required String selfEmail,
  required List<OnlineDriver> peers,
  ({double lat, double lng})? selfCoords,
  required DateTime now,
}) {
  final me = normalizeEmail(selfEmail);
  final others = peers.where((d) => d.email != me).toList(growable: true);
  if (selfCoords != null) {
    others.add(OnlineDriver(
      email: me,
      lat: selfCoords.lat,
      lng: selfCoords.lng,
    ));
  }

  double? distanceKm;
  final pc = ride.pickupCoords;
  if (selfCoords != null && pc != null) {
    distanceKm = haversineKm(selfCoords.lat, selfCoords.lng, pc.lat, pc.lng);
  }

  final ranking = rankDriversForRide(ride, others);
  final myRank = ranking.indexOf(me);
  final depth = currentOfferDepth(ride, now);
  final offered = myRank >= 0 && myRank < depth;

  return OfferedRide(
    ride: ride,
    distanceKm: distanceKm,
    myRank: myRank,
    offerDepth: depth,
    totalRanked: ranking.length,
    offered: offered,
    isSolo: ranking.length <= 1,
  );
}
