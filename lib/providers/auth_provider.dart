import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/driver.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// All Riverpod-graph entry points related to authentication and the
/// signed-in driver's profile. Keeping them in one file makes the
/// dependency graph easy to read at a glance.

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseAuthProvider));
});

final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService(ref.watch(firestoreProvider));
});

/// Stream of the currently-signed-in Firebase user (or null).
/// Used by the router to redirect protected routes.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// The driver profile doc for the signed-in user. Emits `null` when
/// either no user is signed in OR the doc has not yet been created
/// (very brief window during register).
final currentDriverProvider = StreamProvider<Driver?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user?.email == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchDriver(user!.email!);
});
