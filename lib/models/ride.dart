import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

enum RideStatus { searching, accepted, inTransit, completed, cancelled, unknown }

RideStatus rideStatusFromString(String? raw) {
  switch (raw) {
    case AppConstants.rideSearching:
      return RideStatus.searching;
    case AppConstants.rideAccepted:
      return RideStatus.accepted;
    case AppConstants.rideInTransit:
      return RideStatus.inTransit;
    case AppConstants.rideCompleted:
      return RideStatus.completed;
    case AppConstants.rideCancelled:
      return RideStatus.cancelled;
    default:
      return RideStatus.unknown;
  }
}

String rideStatusToString(RideStatus s) {
  switch (s) {
    case RideStatus.searching:
      return AppConstants.rideSearching;
    case RideStatus.accepted:
      return AppConstants.rideAccepted;
    case RideStatus.inTransit:
      return AppConstants.rideInTransit;
    case RideStatus.completed:
      return AppConstants.rideCompleted;
    case RideStatus.cancelled:
      return AppConstants.rideCancelled;
    case RideStatus.unknown:
      return AppConstants.rideSearching;
  }
}

/// Lat/lng pair stored as a plain Firestore map. We deliberately avoid
/// `GeoPoint` so the same shape works on the React web app and so
/// queries can read individual fields without unwrapping a class.
class GeoCoords {
  final double lat;
  final double lng;
  final double? accuracy;

  const GeoCoords({required this.lat, required this.lng, this.accuracy});

  factory GeoCoords.fromMap(Map<String, dynamic> map) => GeoCoords(
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        accuracy: (map['accuracy'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
      };
}

class Ride {
  final String id;
  final String pickup;
  final String dropoff;
  final String? notes;
  final String commuter;
  final String commuterPhone;
  final RideStatus status;
  final String? assignedDriver;
  final GeoCoords? driverLocation;
  final GeoCoords? pickupCoords;
  final DateTime? scheduledFor;
  final int? rating;
  final String? feedback;
  final DateTime? ratedAt;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? onboardAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelledBy;

  const Ride({
    required this.id,
    required this.pickup,
    required this.dropoff,
    required this.commuter,
    required this.commuterPhone,
    required this.status,
    this.notes,
    this.assignedDriver,
    this.driverLocation,
    this.pickupCoords,
    this.scheduledFor,
    this.rating,
    this.feedback,
    this.ratedAt,
    this.createdAt,
    this.acceptedAt,
    this.onboardAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelledBy,
  });

  bool get isScheduled => scheduledFor != null;
  bool get isRated => rating != null;

  factory Ride.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    GeoCoords? coordsOf(String key) {
      final raw = d[key];
      if (raw is Map<String, dynamic>) return GeoCoords.fromMap(raw);
      if (raw is Map) return GeoCoords.fromMap(Map<String, dynamic>.from(raw));
      return null;
    }

    return Ride(
      id: doc.id,
      pickup: (d['pickup'] as String?) ?? '',
      dropoff: (d['dropoff'] as String?) ?? '',
      notes: d['notes'] as String?,
      commuter: (d['commuter'] as String?) ?? '',
      commuterPhone: (d['commuterPhone'] as String?) ?? '',
      status: rideStatusFromString(d['status'] as String?),
      assignedDriver: d['assignedDriver'] as String?,
      driverLocation: coordsOf('driverLocation'),
      pickupCoords: coordsOf('pickupCoords'),
      scheduledFor: (d['scheduledFor'] as Timestamp?)?.toDate(),
      rating: (d['rating'] as num?)?.toInt(),
      feedback: d['feedback'] as String?,
      ratedAt: (d['ratedAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      acceptedAt: (d['acceptedAt'] as Timestamp?)?.toDate(),
      onboardAt: (d['onboardAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      cancelledAt: (d['cancelledAt'] as Timestamp?)?.toDate(),
      cancelledBy: d['cancelledBy'] as String?,
    );
  }

  /// Initial map written by the commuter. Status MUST be "searching"
  /// and assignedDriver MUST be null — Firestore rules enforce both.
  Map<String, dynamic> toCreateMap() => {
        'pickup': pickup,
        'dropoff': dropoff,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'commuter': commuter,
        'commuterPhone': commuterPhone,
        'status': AppConstants.rideSearching,
        'assignedDriver': null,
        if (pickupCoords != null) 'pickupCoords': pickupCoords!.toMap(),
        if (scheduledFor != null)
          'scheduledFor': Timestamp.fromDate(scheduledFor!),
        'createdAt': FieldValue.serverTimestamp(),
      };
}
