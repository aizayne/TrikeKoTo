/// App-wide tunables. Centralised so the matching algorithm is one
/// edit away from being re-tuned during a thesis defense demo.
class AppConstants {
  AppConstants._();

  /// Drivers more than this distance from a pickup are not eligible
  /// for the ride (greedy nearest-driver matching).
  static const double proximityKm = 5.0;

  /// Each 15s the offer widens by one rank (0 → 1 → 2 …).
  static const Duration offerExpand = Duration(seconds: 15);

  /// Hard cap on offer depth — at most 10 drivers ever see one ride.
  static const int maxOfferDepth = 10;

  /// Rides older than this are removed from a driver's queue
  /// regardless of status; safety net for stuck searching rides.
  static const Duration rideQueueWindow = Duration(minutes: 10);

  /// Scheduled rides only enter the acceptance queue when their
  /// scheduledFor time is within this window.
  static const Duration scheduledLeadTime = Duration(minutes: 15);

  /// Min/max bounds for scheduled-for inputs (commuter side).
  static const Duration minScheduleAhead = Duration(minutes: 5);
  static const Duration maxScheduleAhead = Duration(days: 7);

  /// Rating bounds (Firestore rule enforces the same).
  static const int minRating = 1;
  static const int maxRating = 5;

  /// Feedback message length bounds (Firestore rule enforces too).
  static const int feedbackMinChars = 1;
  static const int feedbackMaxChars = 2000;

  /// Default map centre — Barangay Balaybay Resettlement, Castillejos, Zambales.
  static const double balaybayLat = 14.9408;
  static const double balaybayLng = 120.2008;

  /// Driver status strings — must match Firestore values byte-for-byte.
  static const driverPending = 'Pending Verification';
  static const driverActive = 'Active';
  static const driverSuspended = 'Suspended';

  /// Ride status strings — must match Firestore values byte-for-byte.
  ///
  /// Lifecycle:  searching → accepted → in_transit → completed
  ///                                  ↘ cancelled (from any pre-completed state)
  ///
  /// `accepted` covers driver-en-route-to-pickup; `in_transit` covers
  /// passenger-onboard-en-route-to-dropoff. The split lets the commuter
  /// keep seeing the live map for the entire ride (not just the pickup
  /// leg) and gives the admin a finer view of the active fleet.
  static const rideSearching = 'searching';
  static const rideAccepted = 'accepted';
  static const rideInTransit = 'in_transit';
  static const rideCompleted = 'completed';
  static const rideCancelled = 'cancelled';

  /// Values written to `cancelledBy` on a cancelled ride. Used by the
  /// admin dashboard to attribute cancellations.
  static const cancelledByCommuter = 'commuter';
  static const cancelledByDriver = 'driver';
  static const cancelledByDriverWentOffline = 'driver_went_offline';
}
