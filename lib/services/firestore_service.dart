import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../core/utils/email.dart';
import '../models/driver.dart';
import '../models/feedback.dart';
import '../models/ride.dart';

/// Sentinel exception used by [FirestoreService.acceptRide] when the
/// atomic transaction loses to another driver. The dashboard catches
/// these and quietly hides the card instead of toasting an error.
class RideAcceptanceException implements Exception {
  /// One of: 'GONE' (ride deleted), 'ALREADY_TAKEN' (status moved
  /// past `searching` before our transaction committed).
  final String code;
  const RideAcceptanceException(this.code);
  @override
  String toString() => 'RideAcceptanceException($code)';
}

/// Single point of contact with Firestore. Wrapping reads/writes here
/// makes the security model auditable from one file and lets the rest
/// of the app deal in domain types (`Driver`, `Ride`) instead of raw
/// `Map<String, dynamic>`.
class FirestoreService {
  FirestoreService(this._db);

  final FirebaseFirestore _db;

  // ── Drivers ──────────────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _driverDoc(String email) =>
      _db.collection('drivers').doc(normalizeEmail(email));

  Future<Driver?> getDriver(String email) async {
    final snap = await _driverDoc(email).get();
    if (!snap.exists) return null;
    return Driver.fromFirestore(snap);
  }

  Stream<Driver?> watchDriver(String email) {
    return _driverDoc(email).snapshots().map(
          (snap) => snap.exists ? Driver.fromFirestore(snap) : null,
        );
  }

  /// Creates the driver profile right after Auth registration.
  /// Throws if the doc already exists (Firestore rule blocks overwrite).
  Future<void> createDriver(Driver driver) async {
    await _driverDoc(driver.email).set(driver.toCreateMap());
  }

  Future<void> updateDriverProfile(Driver driver) async {
    await _driverDoc(driver.email).update(driver.toProfileUpdateMap());
  }

  // ── Active drivers (online presence) ─────────────────────────────────────

  DocumentReference<Map<String, dynamic>> activeDriverDoc(String email) =>
      _db.collection('active_drivers').doc(normalizeEmail(email));

  /// Toggle the driver's online state. Uses `set(..., merge: true)` so the
  /// doc is created the first time and re-used on subsequent toggles —
  /// avoids a separate "exists?" round-trip.
  Future<void> setDriverPresence({
    required String email,
    required bool isOnline,
    GeoCoords? location,
    String? fcmToken,
  }) {
    return activeDriverDoc(email).set({
      'email': normalizeEmail(email),
      'isOnline': isOnline,
      if (location != null) 'location': location.toMap(),
      'fcmToken': ?fcmToken,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Lightweight per-tick location update. Skips touching `isOnline` so
  /// going offline elsewhere isn't accidentally reverted by a late
  /// position event.
  Future<void> updateDriverLocation({
    required String email,
    required GeoCoords location,
  }) {
    return activeDriverDoc(email).set({
      'location': location.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stamps the FCM registration token onto the driver's presence doc so
  /// a Cloud Function can target push notifications at this device.
  /// Uses `set(..., merge: true)` so this works even before the driver
  /// has gone online (no `isOnline` field yet).
  Future<void> updateFcmToken({
    required String email,
    required String token,
  }) {
    return activeDriverDoc(email).set({
      'email': normalizeEmail(email),
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream of online drivers. The matcher will consume this in step 4
  /// to compute the greedy ranking on every position tick.
  Stream<List<Map<String, dynamic>>> watchOnlineDrivers() {
    return _db
        .collection('active_drivers')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Live `location` map of one specific driver. Emits null while the
  /// doc is missing, the driver is offline, or no GPS fix exists yet.
  /// Used by the commuter's accepted-phase map to track the driver in
  /// real time without re-reading the whole online-drivers list.
  Stream<GeoCoords?> watchDriverLocation(String email) {
    return activeDriverDoc(email).snapshots().map((snap) {
      if (!snap.exists) return null;
      final loc = snap.data()?['location'];
      if (loc is! Map) return null;
      return GeoCoords.fromMap(Map<String, dynamic>.from(loc));
    });
  }

  // ── Rides ────────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get rides =>
      _db.collection('rides');

  Future<DocumentReference<Map<String, dynamic>>> createRide(Ride ride) {
    return rides.add(ride.toCreateMap());
  }

  Stream<Ride> watchRide(String rideId) {
    return rides.doc(rideId).snapshots().map(Ride.fromFirestore);
  }

  /// Cancel a ride from the commuter side. The Firestore rule allows
  /// this for any ride still in `searching` or `accepted`. Always
  /// stamps `cancelledAt` so analytics can compute time-to-cancel.
  Future<void> cancelRide(String rideId) {
    return rides.doc(rideId).update({
      'status': AppConstants.rideCancelled,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': AppConstants.cancelledByCommuter,
    });
  }

  /// Atomic acceptance — wrapped in a transaction so that if two
  /// drivers tap "Accept" simultaneously, Firestore serialises them
  /// and only the first commit wins. The loser sees their re-read
  /// status as `accepted` and we throw [RideAcceptanceException]
  /// with code `ALREADY_TAKEN`.
  ///
  /// `driverLocation` is stored as a flat `{lat, lng}` map (no
  /// accuracy) — this matches the React reference and keeps the
  /// commuter's map projection simple.
  Future<void> acceptRide({
    required String rideId,
    required String driverEmail,
    ({double lat, double lng})? driverLocation,
  }) async {
    final email = normalizeEmail(driverEmail);
    final ref = rides.doc(rideId);
    await _db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const RideAcceptanceException('GONE');
      }
      final status = snap.data()?['status'] as String?;
      if (status != AppConstants.rideSearching) {
        throw const RideAcceptanceException('ALREADY_TAKEN');
      }
      tx.update(ref, {
        'status': AppConstants.rideAccepted,
        'assignedDriver': email,
        'driverLocation': driverLocation == null
            ? null
            : {'lat': driverLocation.lat, 'lng': driverLocation.lng},
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Driver-side completion. Firestore rule requires the caller to be
  /// the assigned driver; the next-state must be `completed`.
  Future<void> completeRide(String rideId) {
    return rides.doc(rideId).update({
      'status': AppConstants.rideCompleted,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Driver-side cancellation (manual). Distinct from the commuter
  /// cancel and from going-offline cancellation, which uses
  /// [cancelRideOnDriverWentOffline] so the admin dashboard can tell
  /// "I changed my mind" from "I lost the gig because they went home".
  Future<void> driverCancelRide(String rideId) {
    return rides.doc(rideId).update({
      'status': AppConstants.rideCancelled,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': AppConstants.cancelledByDriver,
    });
  }

  Future<void> cancelRideOnDriverWentOffline(String rideId) {
    return rides.doc(rideId).update({
      'status': AppConstants.rideCancelled,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': AppConstants.cancelledByDriverWentOffline,
    });
  }

  /// Stream of rides currently in `searching` status. Drivers use this
  /// as the input to the matcher; commuters watch a single ride doc
  /// instead via [watchRide].
  Stream<List<Ride>> watchSearchingRides() {
    return rides
        .where('status', isEqualTo: AppConstants.rideSearching)
        .snapshots()
        .map((s) => s.docs.map(Ride.fromFirestore).toList());
  }

  /// Every ride ever assigned to this driver, regardless of status.
  /// Sorted newest-first. Used by the driver's Ride History screen.
  ///
  /// We sort client-side (instead of `.orderBy('createdAt')`) so the
  /// query stays single-field and avoids needing a composite index in
  /// Firestore — the result set per driver is small enough for that
  /// to be a non-issue.
  Stream<List<Ride>> watchRidesForDriver(String driverEmail) {
    final email = normalizeEmail(driverEmail);
    return rides
        .where('assignedDriver', isEqualTo: email)
        .snapshots()
        .map((s) {
      final list = s.docs.map(Ride.fromFirestore).toList();
      list.sort((a, b) {
        final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  /// The ride doc currently assigned to this driver and not yet
  /// completed. We only ever expect 0 or 1 — the accept transaction
  /// guarantees a driver can't grab a second ride while one is live —
  /// so we collapse the snapshot down to a single nullable.
  Stream<Ride?> watchActiveRideFor(String driverEmail) {
    final email = normalizeEmail(driverEmail);
    return rides
        .where('assignedDriver', isEqualTo: email)
        .where('status', isEqualTo: AppConstants.rideAccepted)
        .snapshots()
        .map((s) {
      if (s.docs.isEmpty) return null;
      // Newest first, just in case of any straggler doc.
      final docs = s.docs.toList()
        ..sort((a, b) {
          final ta = (a.data()['acceptedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final tb = (b.data()['acceptedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });
      return Ride.fromFirestore(docs.first);
    });
  }

  /// Commuter-side rating. Firestore rules enforce three things we
  /// don't double-check here:
  ///   - the caller booked the ride (commuter check is implicit)
  ///   - rating is in [1..5]
  ///   - the doc was not already rated (rate-once)
  /// We trim and null-out an empty comment so analytics queries don't
  /// have to special-case empty strings.
  Future<void> rateRide({
    required String rideId,
    required int rating,
    String? feedback,
  }) {
    final trimmed = feedback?.trim();
    return rides.doc(rideId).update({
      'rating': rating,
      'feedback': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      'ratedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Admin gate ───────────────────────────────────────────────────────────

  /// Returns true when an `admins/{email}` doc exists. The Firestore
  /// rule restricts reads to admins themselves, so a denied read is
  /// indistinguishable from "not an admin" — both resolve to `false`.
  Future<bool> isAdmin(String email) async {
    try {
      final snap =
          await _db.collection('admins').doc(normalizeEmail(email)).get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  // ── Admin reads ──────────────────────────────────────────────────────────

  /// Live snapshot of every driver. Public read in our rules, but the
  /// admin screens are the only consumer in the app today.
  Stream<List<Driver>> watchAllDrivers() {
    return _db.collection('drivers').snapshots().map(
          (s) => s.docs.map(Driver.fromFirestore).toList(),
        );
  }

  /// Live snapshot of every ride doc. Used by the admin analytics page
  /// for stat aggregation, the 7-day chart, ratings, and top drivers.
  Stream<List<Ride>> watchAllRides() {
    return rides.snapshots().map(
          (s) => s.docs.map(Ride.fromFirestore).toList(),
        );
  }

  /// Live snapshot of every active_drivers doc (online + offline). The
  /// admin dashboard counts `isOnline == true` to show "online now".
  Stream<List<Map<String, dynamic>>> watchAllActiveDrivers() {
    return _db.collection('active_drivers').snapshots().map(
          (s) => s.docs.map((d) => d.data()).toList(),
        );
  }

  /// Live snapshot of feedback submissions. Sorted newest-first so the
  /// admin panel can paginate from the top.
  Stream<List<FeedbackEntry>> watchAllFeedback() {
    return _db.collection('feedback').snapshots().map((s) {
      final out = s.docs.map(FeedbackEntry.fromFirestore).toList();
      out.sort((a, b) {
        final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
      return out;
    });
  }

  /// Admin-only: flip a driver's `status` between Active / Suspended /
  /// Pending Verification. Firestore rule enforces that only an admin
  /// (and only on the `status` triplet of fields) may write here, so
  /// non-admins will see a permission-denied error if they try.
  Future<void> updateDriverStatus({
    required String driverEmail,
    required String newStatus,
    required String adminEmail,
  }) {
    return _driverDoc(driverEmail).update({
      'status': newStatus,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'statusUpdatedBy': normalizeEmail(adminEmail),
    });
  }

  // ── Feedback ─────────────────────────────────────────────────────────────

  Future<DocumentReference<Map<String, dynamic>>> createFeedback(
      FeedbackEntry entry) {
    return _db.collection('feedback').add(entry.toCreateMap());
  }
}
