import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/driver.dart';
import '../models/feedback.dart';
import '../models/ride.dart';
import 'auth_provider.dart';

/// Riverpod entry points used by the two admin screens. The `admins`
/// collection is rule-gated to admins only — every stream below will
/// fail with permission-denied for a signed-in non-admin, which the
/// screens treat as the access-denied path.

/// Resolves to true when the signed-in user has an `admins/{email}`
/// doc. Used by the router-level guards on /admin and /admin/dashboard.
/// Errors (including permission-denied) collapse to `false`.
final isAdminProvider = FutureProvider.autoDispose<bool>((ref) async {
  final email = ref.watch(authServiceProvider).currentEmail;
  if (email == null) return false;
  return ref.watch(firestoreServiceProvider).isAdmin(email);
});

final allDriversProvider = StreamProvider.autoDispose<List<Driver>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllDrivers();
});

final allRidesProvider = StreamProvider.autoDispose<List<Ride>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllRides();
});

final allActiveDriversProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllActiveDrivers();
});

final allFeedbackProvider =
    StreamProvider.autoDispose<List<FeedbackEntry>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllFeedback();
});
