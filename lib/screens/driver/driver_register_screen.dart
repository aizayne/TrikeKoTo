import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../core/utils/email.dart';
import '../../models/driver.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';

/// New-driver signup. Two-step Firebase work:
///   1. createUserWithEmailAndPassword — gives us a uid + signed-in session
///   2. drivers/{email}.set with status: "Pending Verification"
/// If step 2 fails (e.g. doc already exists), we sign the user back out
/// so they don't sit in a half-registered state.
class DriverRegisterScreen extends ConsumerStatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  ConsumerState<DriverRegisterScreen> createState() =>
      _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends ConsumerState<DriverRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [
      _email,
      _password,
      _confirmPassword,
      _firstName,
      _lastName,
      _phone,
      _plate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    final auth = ref.read(authServiceProvider);
    final db = ref.read(firestoreServiceProvider);
    final email = normalizeEmail(_email.text);

    try {
      await auth.register(email: email, password: _password.text);

      final driver = Driver(
        email: email,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        plateNumber: _plate.text.trim().toUpperCase(),
        status: DriverStatus.pending,
      );

      try {
        await db.createDriver(driver);
      } catch (e) {
        // Profile write failed — fully delete the just-created Auth
        // account so the email is freed up and the user can retry.
        // Best-effort: if delete itself fails (e.g. requires recent
        // re-auth) we fall back to signOut so we at least don't leave
        // them logged in to an orphaned account.
        try {
          await auth.deleteCurrentUser();
        } catch (_) {
          await auth.signOut();
        }
        rethrow;
      }

      // Sign out so /driver/pending is reached as an unauthenticated
      // user — protects against accidentally landing on dashboard.
      await auth.signOut();
      if (!mounted) return;
      context.go('/driver/pending');
    } on FirebaseAuthException catch (e) {
      _toast(_humanAuthError(e));
    } catch (e) {
      _toast('Registration failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email is already registered. Try signing in.';
      case 'invalid-email':
        return 'That email doesn\'t look right.';
      case 'weak-password':
        return 'Password is too weak — use at least 8 characters with a letter and a number.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return e.message ?? 'Registration failed.';
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.go('/driver/login'),
        ),
        title: const Text('Driver registration'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Text(
                  'Create your driver account',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  "An admin will review your details before you can go online.",
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstName,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                        ),
                        textInputAction: TextInputAction.next,
                        validator: _required('First name'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastName,
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                        ),
                        textInputAction: TextInputAction.next,
                        validator: _required('Last name'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(LucideIcons.phone, size: 18),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Phone is required';
                    if (t.replaceAll(RegExp(r'[^\d]'), '').length < 7) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(15),
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-\s]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Plate number',
                    prefixIcon: Icon(LucideIcons.tag, size: 18),
                  ),
                  validator: _required('Plate number'),
                ),
                const SizedBox(height: 24),
                const Divider(color: AppColors.surfaceAlt, height: 1),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(LucideIcons.mail, size: 18),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Email is required';
                    if (!t.contains('@') || !t.contains('.')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 8 characters, mix letters & numbers',
                    helperStyle: const TextStyle(color: AppColors.muted),
                    prefixIcon: const Icon(LucideIcons.lock, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    final t = v ?? '';
                    if (t.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    if (!RegExp(r'[A-Za-z]').hasMatch(t) ||
                        !RegExp(r'[0-9]').hasMatch(t)) {
                      return 'Password must include both letters and numbers';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: Icon(LucideIcons.lock, size: 18),
                  ),
                  validator: (v) {
                    if ((v ?? '') != _password.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Create account',
                  icon: LucideIcons.userPlus,
                  busy: _busy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/driver/login'),
                    child: const Text('Already have an account? Sign in'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? Function(String?) _required(String label) => (v) =>
      (v ?? '').trim().isEmpty ? '$label is required' : null;
}
