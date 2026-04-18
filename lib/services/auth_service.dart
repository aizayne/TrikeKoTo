import 'package:firebase_auth/firebase_auth.dart';

import '../core/utils/email.dart';

/// Thin wrapper around FirebaseAuth so screens never touch the SDK
/// directly. Keeps email normalisation in one place — every entry
/// point lowercases before talking to Auth or Firestore.
class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;

  User? get currentUser => _auth.currentUser;
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: normalizeEmail(email),
      password: password,
    );
  }

  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: normalizeEmail(email),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Removes the currently signed-in Firebase Auth account. We use this
  /// to roll back a half-finished registration: if the Firestore profile
  /// write fails after `register()` succeeded, deleting the Auth account
  /// frees the email so the user can retry from a clean slate. Plain
  /// `signOut()` would leave an orphaned Auth user that blocks re-use of
  /// the address with `email-already-in-use`.
  Future<void> deleteCurrentUser() async {
    final u = _auth.currentUser;
    if (u != null) await u.delete();
  }

  /// Convenience: returns the lowercased email of the signed-in user, or null.
  String? get currentEmail {
    final raw = _auth.currentUser?.email;
    return raw == null ? null : normalizeEmail(raw);
  }
}
