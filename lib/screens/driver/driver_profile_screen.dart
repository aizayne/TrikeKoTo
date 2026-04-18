import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/driver.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_badge.dart';

/// Profile editor for the signed-in driver. Mirrors the React reference
/// at `trikekoto-web/src/pages/DriverProfile.jsx`.
///
/// Editable fields: firstName, lastName, phone, plateNumber.
/// Read-only: email (identity key) and status (admin-controlled — the
/// Firestore rule's `driverFieldsOk()` would reject any write here).
class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  ConsumerState<DriverProfileScreen> createState() =>
      _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();

  /// The most recently loaded profile. We compare against this snapshot
  /// to detect whether the form has unsaved changes (so the Save button
  /// only lights up when something actually differs).
  Driver? _loaded;
  bool _saving = false;
  bool _hydrated = false;

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _phone, _plate]) {
      c.dispose();
    }
    super.dispose();
  }

  /// One-shot copy of the loaded profile into the controllers. We only
  /// hydrate once per profile load so a re-render from a stream tick
  /// doesn't blow away mid-edit input.
  void _hydrateFrom(Driver d) {
    if (_hydrated) return;
    _firstName.text = d.firstName;
    _lastName.text = d.lastName;
    _phone.text = d.phone;
    _plate.text = d.plateNumber;
    _loaded = d;
    _hydrated = true;
  }

  bool get _hasChanges {
    final base = _loaded;
    if (base == null) return false;
    return _firstName.text.trim() != base.firstName ||
        _lastName.text.trim() != base.lastName ||
        _phone.text.trim() != base.phone ||
        _plate.text.trim().toUpperCase() != base.plateNumber;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final base = _loaded;
    if (base == null) return;

    final updated = Driver(
      email: base.email,
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      phone: _phone.text.trim(),
      plateNumber: _plate.text.trim().toUpperCase(),
      status: base.status,
      createdAt: base.createdAt,
    );

    setState(() => _saving = true);
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateDriverProfile(updated);
      if (!mounted) return;
      // Refresh local baseline so hasChanges resets without waiting
      // for the stream to round-trip through Firestore.
      setState(() => _loaded = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update profile: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverAsync = ref.watch(currentDriverProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.go('/driver/dashboard'),
        ),
        title: const Text('My Profile'),
      ),
      body: SafeArea(
        child: driverAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          ),
          error: (e, _) => _ErrorState(message: 'Could not load profile: $e'),
          data: (driver) {
            if (driver == null) {
              return const _ErrorState(message: 'Profile not found.');
            }
            // Hydrate once. Calling inside build is safe because the
            // method short-circuits on subsequent calls.
            _hydrateFrom(driver);
            return _buildForm(driver);
          },
        ),
      ),
    );
  }

  Widget _buildForm(Driver driver) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        // Re-evaluate the Save button on every keystroke so the disabled
        // state tracks _hasChanges in real time.
        onChanged: () => setState(() {}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AvatarHeader(driver: driver),
            const SizedBox(height: 20),
            _ReadOnlyField(
              label: 'Email',
              icon: LucideIcons.mail,
              value: driver.email,
              hint: 'Email cannot be changed',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstName,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'First name',
                      prefixIcon: Icon(LucideIcons.user, size: 18),
                    ),
                    validator: _required('First name'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastName,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Last name',
                    ),
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
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
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
            PrimaryButton(
              label: _saving
                  ? 'Saving…'
                  : (_hasChanges ? 'Save changes' : 'No changes'),
              icon: LucideIcons.save,
              busy: _saving,
              onPressed: _hasChanges ? _save : null,
            ),
          ],
        ),
      ),
    );
  }

  String? Function(String?) _required(String label) => (v) =>
      (v ?? '').trim().isEmpty ? '$label is required' : null;
}

// ──────────────────────────────────────────────────────────────────────────
// Header: avatar circle + status badge under it
// ──────────────────────────────────────────────────────────────────────────

class _AvatarHeader extends StatelessWidget {
  final Driver driver;
  const _AvatarHeader({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          child: const Icon(LucideIcons.user,
              size: 36, color: AppColors.accent),
        ),
        const SizedBox(height: 12),
        if (driver.fullName.isNotEmpty)
          Text(
            driver.fullName,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        const SizedBox(height: 6),
        _statusBadgeFor(driver.status),
      ],
    );
  }

  Widget _statusBadgeFor(DriverStatus s) {
    switch (s) {
      case DriverStatus.active:
        return const StatusBadge(
          label: 'ACTIVE',
          color: AppColors.success,
          icon: LucideIcons.shieldCheck,
        );
      case DriverStatus.pending:
        return const StatusBadge(
          label: 'PENDING VERIFICATION',
          color: AppColors.warning,
          icon: LucideIcons.shield,
        );
      case DriverStatus.suspended:
        return const StatusBadge(
          label: 'SUSPENDED',
          color: AppColors.danger,
          icon: LucideIcons.shieldAlert,
        );
      case DriverStatus.unknown:
        return const StatusBadge(
          label: 'UNKNOWN',
          color: AppColors.muted,
          icon: LucideIcons.shield,
        );
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Read-only "field" — looks like a TextFormField but isn't editable
// ──────────────────────────────────────────────────────────────────────────

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final String? hint;

  const _ReadOnlyField({
    required this.label,
    required this.icon,
    required this.value,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          enabled: false,
          initialValue: value,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 18, color: AppColors.muted),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: AppColors.surfaceAlt.withValues(alpha: 0.5)),
            ),
          ),
          style: const TextStyle(color: AppColors.muted),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              hint!,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Error / empty state
// ──────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.alertTriangle,
                size: 48, color: AppColors.warning),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => context.go('/driver/dashboard'),
              icon: const Icon(LucideIcons.arrowLeft, size: 14),
              label: const Text('Back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
