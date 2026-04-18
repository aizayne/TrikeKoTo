import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

/// Mirror of `drivers/{emailLowercase}` plus the small slice of
/// `active_drivers/{emailLowercase}` we care about on the client.
///
/// Status is stored as a free-form string in Firestore so the admin can
/// extend it later without a migration; we narrow it back to an enum
/// for type-safe checks in the app.
enum DriverStatus { pending, active, suspended, unknown }

DriverStatus statusFromString(String? raw) {
  switch (raw) {
    case AppConstants.driverActive:
      return DriverStatus.active;
    case AppConstants.driverPending:
      return DriverStatus.pending;
    case AppConstants.driverSuspended:
      return DriverStatus.suspended;
    default:
      return DriverStatus.unknown;
  }
}

String statusToString(DriverStatus s) {
  switch (s) {
    case DriverStatus.active:
      return AppConstants.driverActive;
    case DriverStatus.pending:
      return AppConstants.driverPending;
    case DriverStatus.suspended:
      return AppConstants.driverSuspended;
    case DriverStatus.unknown:
      return AppConstants.driverPending;
  }
}

class Driver {
  final String email;
  final String firstName;
  final String lastName;
  final String phone;
  final String plateNumber;
  final DriverStatus status;
  final DateTime? createdAt;

  const Driver({
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.plateNumber,
    required this.status,
    this.createdAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory Driver.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Driver(
      email: (data['email'] as String?) ?? doc.id,
      firstName: (data['firstName'] as String?) ?? '',
      lastName: (data['lastName'] as String?) ?? '',
      phone: (data['phone'] as String?) ?? '',
      plateNumber: (data['plateNumber'] as String?) ?? '',
      status: statusFromString(data['status'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Used on initial registration. `status` is forced to "Pending
  /// Verification" because Firestore rules will reject any other
  /// initial value from the client.
  Map<String, dynamic> toCreateMap() => {
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'plateNumber': plateNumber,
        'status': AppConstants.driverPending,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Used by the driver editing their own profile. Note that `status`
  /// is intentionally absent — the client-side rule blocks it anyway,
  /// but we keep the surface tight here too.
  Map<String, dynamic> toProfileUpdateMap() => {
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'plateNumber': plateNumber,
      };
}
