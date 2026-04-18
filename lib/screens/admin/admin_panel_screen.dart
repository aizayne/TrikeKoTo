import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/driver.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';

/// Admin-only driver management. Mirrors the React `/#/admin` page:
///   - Status filter pills (All / Pending / Active / Suspended)
///   - Stat cards above the table
///   - Approve / Suspend per-row actions (writes via Firestore service)
///
/// Access control: we resolve [isAdminProvider] before showing any data.
/// `checking` shows a loader, `false` shows a polite access-denied panel
/// — the Firestore rules also block the reads below for non-admins, so
/// the gate is belt-and-braces.
class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen> {
  /// One of: 'All' | driverPending | driverActive | driverSuspended.
  String _filter = 'All';

  /// Email of the row currently being mutated, used to disable both
  /// action buttons during the round-trip.
  String? _updating;

  Future<void> _setStatus(Driver driver, String newStatus) async {
    final adminEmail = ref.read(authServiceProvider).currentEmail;
    if (adminEmail == null) return;

    setState(() => _updating = driver.email);
    try {
      await ref.read(firestoreServiceProvider).updateDriverStatus(
            driverEmail: driver.email,
            newStatus: newStatus,
            adminEmail: adminEmail,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${driver.email} → $newStatus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update driver status. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adminCheck = ref.watch(isAdminProvider);

    return adminCheck.when(
      loading: () => const _AdminLoading(message: 'Verifying admin access…'),
      error: (_, _) => const _AccessDenied(),
      data: (isAdmin) {
        if (!isAdmin) return const _AccessDenied();
        return _AdminPanelBody(
          filter: _filter,
          onFilterChanged: (f) => setState(() => _filter = f),
          updatingEmail: _updating,
          onSetStatus: _setStatus,
        );
      },
    );
  }
}

class _AdminPanelBody extends ConsumerWidget {
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final String? updatingEmail;
  final Future<void> Function(Driver driver, String newStatus) onSetStatus;

  const _AdminPanelBody({
    required this.filter,
    required this.onFilterChanged,
    required this.updatingEmail,
    required this.onSetStatus,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driversAsync = ref.watch(allDriversProvider);
    final adminEmail = ref.watch(authServiceProvider).currentEmail ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          'TrikeKoTo Admin',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/admin/dashboard'),
            icon: const Icon(LucideIcons.barChart3, size: 16),
            label: const Text('Dashboard'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(LucideIcons.logOut),
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
              if (!context.mounted) return;
              context.go('/');
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: driversAsync.when(
        loading: () => const _AdminLoading(message: 'Loading drivers…'),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load drivers: $e',
              style: const TextStyle(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (drivers) {
          final counts = _countByStatus(drivers);
          final sorted = _sortPendingFirst(drivers);
          final filtered = filter == 'All'
              ? sorted
              : sorted
                  .where((d) => statusToString(d.status) == filter)
                  .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Driver Management · $adminEmail',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _StatsRow(counts: counts),
                const SizedBox(height: 16),
                _FilterRow(
                  active: filter,
                  counts: counts,
                  onChanged: onFilterChanged,
                ),
                const SizedBox(height: 12),
                _DriverList(
                  drivers: filtered,
                  updatingEmail: updatingEmail,
                  onApprove: (d) => onSetStatus(d, AppConstants.driverActive),
                  onSuspend: (d) =>
                      onSetStatus(d, AppConstants.driverSuspended),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Map<String, int> _countByStatus(List<Driver> drivers) {
    final c = {
      'total': drivers.length,
      AppConstants.driverPending: 0,
      AppConstants.driverActive: 0,
      AppConstants.driverSuspended: 0,
    };
    for (final d in drivers) {
      final key = statusToString(d.status);
      if (c.containsKey(key)) c[key] = c[key]! + 1;
    }
    return c;
  }

  /// React reference rule: pending bucket first, then by registration
  /// time ascending (older registrations float to the top within their
  /// bucket so the oldest waiting driver is visible without scrolling).
  List<Driver> _sortPendingFirst(List<Driver> drivers) {
    int order(DriverStatus s) {
      switch (s) {
        case DriverStatus.pending:
          return 0;
        case DriverStatus.active:
          return 1;
        case DriverStatus.suspended:
          return 2;
        case DriverStatus.unknown:
          return 3;
      }
    }

    final list = drivers.toList()
      ..sort((a, b) {
        final oa = order(a.status);
        final ob = order(b.status);
        if (oa != ob) return oa.compareTo(ob);
        final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return ta.compareTo(tb);
      });
    return list;
  }
}

class _StatsRow extends StatelessWidget {
  final Map<String, int> counts;
  const _StatsRow({required this.counts});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _StatCard(
          color: AppColors.muted,
          number: counts['total'] ?? 0,
          label: 'Total Drivers',
        ),
        _StatCard(
          color: AppColors.warning,
          number: counts[AppConstants.driverPending] ?? 0,
          label: 'Pending Review',
        ),
        _StatCard(
          color: AppColors.success,
          number: counts[AppConstants.driverActive] ?? 0,
          label: 'Active',
        ),
        _StatCard(
          color: AppColors.danger,
          number: counts[AppConstants.driverSuspended] ?? 0,
          label: 'Suspended',
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final Color color;
  final int number;
  final String label;

  const _StatCard({
    required this.color,
    required this.number,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 130),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$number',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String active;
  final Map<String, int> counts;
  final ValueChanged<String> onChanged;

  const _FilterRow({
    required this.active,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      'All',
      AppConstants.driverPending,
      AppConstants.driverActive,
      AppConstants.driverSuspended,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final opt in options)
          _FilterPill(
            label: opt == 'All' ? 'All' : '$opt (${counts[opt] ?? 0})',
            active: active == opt,
            onTap: () => onChanged(opt),
          ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.accent : AppColors.surfaceAlt,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.accent : AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DriverList extends StatelessWidget {
  final List<Driver> drivers;
  final String? updatingEmail;
  final ValueChanged<Driver> onApprove;
  final ValueChanged<Driver> onSuspend;

  const _DriverList({
    required this.drivers,
    required this.updatingEmail,
    required this.onApprove,
    required this.onSuspend,
  });

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'No drivers found.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final d in drivers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DriverCard(
              driver: d,
              isUpdating: updatingEmail == d.email,
              onApprove: () => onApprove(d),
              onSuspend: () => onSuspend(d),
            ),
          ),
      ],
    );
  }
}

class _DriverCard extends StatelessWidget {
  final Driver driver;
  final bool isUpdating;
  final VoidCallback onApprove;
  final VoidCallback onSuspend;

  const _DriverCard({
    required this.driver,
    required this.isUpdating,
    required this.onApprove,
    required this.onSuspend,
  });

  @override
  Widget build(BuildContext context) {
    final canApprove = driver.status != DriverStatus.active;
    final canSuspend = driver.status != DriverStatus.suspended;
    final registered = driver.createdAt != null
        ? DateFormat('MMM d, yyyy').format(driver.createdAt!)
        : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.fullName.isEmpty ? '(no name)' : driver.fullName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      driver.email,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _DriverStatusBadge(status: driver.status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _MetaChip(
                icon: LucideIcons.phone,
                label: driver.phone.isEmpty ? '—' : driver.phone,
              ),
              _MetaChip(
                icon: LucideIcons.car,
                label: driver.plateNumber.isEmpty ? '—' : driver.plateNumber,
                emphasis: true,
              ),
              _MetaChip(
                icon: LucideIcons.calendar,
                label: 'Registered $registered',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (canApprove)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ActionButton(
                    icon: LucideIcons.checkCircle,
                    label: 'Approve',
                    color: AppColors.success,
                    onPressed: isUpdating ? null : onApprove,
                  ),
                ),
              if (canSuspend)
                _ActionButton(
                  icon: LucideIcons.xCircle,
                  label: 'Suspend',
                  color: AppColors.danger,
                  onPressed: isUpdating ? null : onSuspend,
                ),
              if (isUpdating) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Saving…',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasis;
  const _MetaChip({
    required this.icon,
    required this.label,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.muted),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: AppColors.text.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: emphasis ? 0.5 : 0,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      icon: Icon(icon, size: 14, color: color),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DriverStatusBadge extends StatelessWidget {
  final DriverStatus status;
  const _DriverStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      DriverStatus.active => ('Active', AppColors.success),
      DriverStatus.pending => ('Pending', AppColors.warning),
      DriverStatus.suspended => ('Suspended', AppColors.danger),
      DriverStatus.unknown => ('Unknown', AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _AdminLoading extends StatelessWidget {
  final String message;
  const _AdminLoading({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessDenied extends ConsumerWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authServiceProvider).currentEmail ?? '';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.xCircle,
                  size: 44, color: AppColors.danger),
              const SizedBox(height: 12),
              const Text(
                'Access Denied',
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email.isEmpty
                    ? 'You must be signed in as an admin.'
                    : 'Your account ($email) is not in the admin list.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(LucideIcons.arrowLeft, size: 14),
                    label: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(authServiceProvider).signOut();
                      if (!context.mounted) return;
                      context.go('/');
                    },
                    icon: const Icon(LucideIcons.logOut, size: 14),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
