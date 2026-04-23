import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../core/utils/email.dart';
import '../../models/driver.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';

/// Email + password sign-in. After Auth succeeds we read the
/// `drivers/{email}` doc and route based on `status`:
///   Active    → /driver/dashboard
///   Pending   → /driver/pending  (and sign out)
///   Suspended → error toast      (and sign out)
///   Missing   → check admin gate:
///     · admin     → /admin  (stay signed in)
///     · non-admin → error toast (and sign out)
///
/// This is the only auth surface in the app, so we have to handle the
/// admin-only case here too — otherwise admins with no `drivers/` doc
/// would be booted before they could reach /admin.
class DriverLoginScreen extends ConsumerStatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  ConsumerState<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends ConsumerState<DriverLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = ref.read(authServiceProvider);
    final db = ref.read(firestoreServiceProvider);

    try {
      await auth.signIn(
        email: _emailCtrl.text,
        password: _passCtrl.text,
      );

      final email = normalizeEmail(_emailCtrl.text);
      final driver = await db.getDriver(email);

      if (!mounted) return;

      if (driver == null) {
        // No driver doc — last chance to keep them signed in is the
        // admin gate. If the admins/{email} doc exists, send them to
        // the admin panel; otherwise sign them out with a toast.
        final isAdmin = await db.isAdmin(email);
        if (!mounted) return;
        if (isAdmin) {
          context.go('/admin');
          return;
        }
        await auth.signOut();
        _toast('No driver profile found for this account.');
        return;
      }

      switch (driver.status) {
        case DriverStatus.active:
          context.go('/driver/dashboard');
          return;
        case DriverStatus.pending:
        case DriverStatus.unknown:
          await auth.signOut();
          if (mounted) context.go('/driver/pending');
          return;
        case DriverStatus.suspended:
          await auth.signOut();
          _toast('Your account has been suspended. Contact the admin.');
          return;
      }
    } on FirebaseAuthException catch (e) {
      _toast(_humanAuthError(e));
    } catch (e) {
      _toast('Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email doesn\'t look right.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts — try again in a few minutes.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return e.message ?? 'Sign-in failed.';
    }
  }

  /// Opens a small dialog pre-filled with whatever's in the email field,
  /// then sends a password reset email via Firebase Auth.
  ///
  /// We deliberately show the same "If the email exists you'll get a
  /// link" toast for both success AND user-not-found, so an attacker
  /// can't probe which addresses are registered.
  Future<void> _forgotPassword() async {
    final initial = _emailCtrl.text.trim();
    final controller = TextEditingController(text: initial);
    final formKey = GlobalKey<FormState>();

    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter the email for your account. We\'ll send a link '
                'you can use to set a new password.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(LucideIcons.mail, size: 18),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Email is required';
                  if (!t.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(ctx).pop(controller.text.trim());
            },
            child: const Text('Send link'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (email == null || email.isEmpty) return;

    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (!mounted) return;
      _toast('If an account exists for $email, a reset link is on its way.');
    } on FirebaseAuthException catch (e) {
      // Same generic message for user-not-found so we don't leak
      // whether the address is registered.
      if (e.code == 'user-not-found') {
        if (!mounted) return;
        _toast('If an account exists for $email, a reset link is on its way.');
        return;
      }
      _toast(_humanAuthError(e));
    } catch (_) {
      _toast('Could not send reset email. Try again in a moment.');
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
          onPressed: () => context.go('/'),
        ),
        title: const Text('Driver sign in'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const Text(
                  'Welcome back',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sign in with your driver account.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _emailCtrl,
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
                    if (!t.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(LucideIcons.lock, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Password is required' : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Sign in',
                  icon: LucideIcons.logIn,
                  busy: _busy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/driver/register'),
                    child: const Text("Don't have an account? Register"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
