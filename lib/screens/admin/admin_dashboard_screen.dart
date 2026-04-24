import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils/email.dart';
import '../../models/driver.dart';
import '../../models/feedback.dart';
import '../../models/ride.dart';
import '../../providers/admin_provider.dart';

/// Admin-only analytics. Mirrors the React `AdminDashboard.jsx`
/// section-for-section:
///   1. Ride statistics (total, completed, cancelled, in-progress,
///      searching, completion rate %)
///   2. Driver overview (total, approved, pending, suspended, online now)
///   3. Rides last 7 days (horizontal bar chart bucketed by day)
///   4. Commuter satisfaction — average + distribution 5..1
///   5. Recent commuter comments — top 6 rated rides with feedback
///   6. Feedback by category + recent feedback list
///   7. Top drivers by completed-ride count (top 5)
///
/// All data is computed client-side from full-collection streams so the
/// numbers update live as commuters and drivers act.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminCheck = ref.watch(isAdminProvider);
    return adminCheck.when(
      loading: () => const _DashLoading(message: 'Verifying admin access…'),
      error: (_, _) => const _DashAccessDenied(),
      data: (isAdmin) => isAdmin ? const _DashboardBody() : const _DashAccessDenied(),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridesAsync = ref.watch(allRidesProvider);
    final driversAsync = ref.watch(allDriversProvider);
    final activeAsync = ref.watch(allActiveDriversProvider);
    final feedbackAsync = ref.watch(allFeedbackProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () => context.go('/admin'),
        ),
        title: const Text(
          'Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
          ),
        ),
      ),
      body: ridesAsync.when(
        loading: () => const _DashLoading(message: 'Loading dashboard…'),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load rides: $e',
              style: const TextStyle(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (rides) {
          final drivers = driversAsync.valueOrNull ?? const <Driver>[];
          final active = activeAsync.valueOrNull ?? const <Map<String, dynamic>>[];
          final feedback = feedbackAsync.valueOrNull ?? const <FeedbackEntry>[];

          final rideStats = _computeRideStats(rides);
          final driverStats = _computeDriverStats(drivers, active);
          final daily = _computeDailyRides(rides);
          final ratingStats = _computeRatingStats(rides);
          final recentComments = _computeRecentComments(rides);
          final feedbackStats = _computeFeedbackStats(feedback);
          final topDrivers = _computeTopDrivers(rides, drivers);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TrikeKoTo Analytics Overview',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),

                _SectionTitle(icon: LucideIcons.car, label: 'Ride Statistics'),
                const SizedBox(height: 8),
                _StatGrid(items: [
                  _StatItem(AppColors.muted, '${rideStats.total}', 'Total Rides'),
                  _StatItem(AppColors.success, '${rideStats.completed}', 'Completed'),
                  _StatItem(AppColors.danger, '${rideStats.cancelled}', 'Cancelled'),
                  _StatItem(AppColors.info, '${rideStats.accepted}', 'In Progress'),
                  _StatItem(AppColors.warning, '${rideStats.searching}', 'Searching'),
                  _StatItem(AppColors.violet,
                      '${rideStats.completionRate}%', 'Completion Rate'),
                ]),
                const SizedBox(height: 20),

                _SectionTitle(icon: LucideIcons.users, label: 'Driver Overview'),
                const SizedBox(height: 8),
                _StatGrid(items: [
                  _StatItem(AppColors.muted, '${driverStats.total}', 'Total Drivers'),
                  _StatItem(AppColors.success, '${driverStats.active}', 'Approved'),
                  _StatItem(AppColors.warning, '${driverStats.pending}', 'Pending'),
                  _StatItem(AppColors.danger, '${driverStats.suspended}', 'Suspended'),
                  _StatItem(AppColors.info, '${driverStats.online}', 'Online Now'),
                ]),
                const SizedBox(height: 20),

                _SectionTitle(
                    icon: LucideIcons.trendingUp, label: 'Rides — Last 7 Days'),
                const SizedBox(height: 8),
                _DailyBarChart(days: daily),
                const SizedBox(height: 20),

                _SectionTitle(
                    icon: LucideIcons.star, label: 'Commuter Satisfaction'),
                const SizedBox(height: 8),
                _RatingBlock(stats: ratingStats),
                const SizedBox(height: 20),

                if (recentComments.isNotEmpty) ...[
                  _SectionTitle(
                      icon: LucideIcons.messageCircle,
                      label: 'Recent Commuter Comments'),
                  const SizedBox(height: 8),
                  for (final r in recentComments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CommentCard(ride: r),
                    ),
                  const SizedBox(height: 12),
                ],

                _SectionTitle(
                    icon: LucideIcons.alertTriangle,
                    label: 'Feedback & Issue Reports'),
                const SizedBox(height: 8),
                _StatGrid(items: [
                  _StatItem(AppColors.muted, '${feedbackStats.total}', 'Total'),
                  _StatItem(AppColors.danger, '${feedbackStats.issue}', 'Issues'),
                  _StatItem(
                      AppColors.warning, '${feedbackStats.suggestion}', 'Suggestions'),
                  _StatItem(AppColors.info, '${feedbackStats.question}', 'Questions'),
                  _StatItem(
                      AppColors.violet, '${feedbackStats.unresolved}', 'Unresolved'),
                ]),
                const SizedBox(height: 12),
                if (feedback.isEmpty)
                  const _EmptyHint(text: 'No feedback submissions yet.')
                else
                  for (final f in feedback.take(10))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FeedbackCard(entry: f),
                    ),
                const SizedBox(height: 20),

                _SectionTitle(
                    icon: LucideIcons.activity,
                    label: 'Top Drivers (Completed Rides)'),
                const SizedBox(height: 8),
                if (topDrivers.isEmpty)
                  const _EmptyHint(text: 'No completed rides yet.')
                else
                  _TopDriversTable(rows: topDrivers),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Derived stats ────────────────────────────────────────────────────────

class _RideStats {
  final int total;
  final int searching;
  final int accepted;
  final int completed;
  final int cancelled;
  final int completionRate;

  const _RideStats({
    required this.total,
    required this.searching,
    required this.accepted,
    required this.completed,
    required this.cancelled,
    required this.completionRate,
  });
}

_RideStats _computeRideStats(List<Ride> rides) {
  int s = 0, a = 0, c = 0, x = 0;
  for (final r in rides) {
    switch (r.status) {
      case RideStatus.searching:
        s++;
        break;
      case RideStatus.accepted:
      case RideStatus.inTransit:
        // Both states are "an active ride in progress" from the admin's
        // point of view. Lumping them keeps the existing 'In Progress'
        // tile accurate without adding a separate card.
        a++;
        break;
      case RideStatus.completed:
        c++;
        break;
      case RideStatus.cancelled:
        x++;
        break;
      case RideStatus.unknown:
        break;
    }
  }
  final total = rides.length;
  final rate = total > 0 ? ((c / total) * 100).round() : 0;
  return _RideStats(
    total: total,
    searching: s,
    accepted: a,
    completed: c,
    cancelled: x,
    completionRate: rate,
  );
}

class _DriverStats {
  final int total, pending, active, suspended, online;
  const _DriverStats({
    required this.total,
    required this.pending,
    required this.active,
    required this.suspended,
    required this.online,
  });
}

_DriverStats _computeDriverStats(
    List<Driver> drivers, List<Map<String, dynamic>> active) {
  int p = 0, a = 0, s = 0;
  for (final d in drivers) {
    switch (d.status) {
      case DriverStatus.pending:
        p++;
        break;
      case DriverStatus.active:
        a++;
        break;
      case DriverStatus.suspended:
        s++;
        break;
      case DriverStatus.unknown:
        break;
    }
  }
  final online = active.where((m) => m['isOnline'] == true).length;
  return _DriverStats(
    total: drivers.length,
    pending: p,
    active: a,
    suspended: s,
    online: online,
  );
}

class _DailyRideCount {
  final String label;
  final int count;
  const _DailyRideCount({required this.label, required this.count});
}

List<_DailyRideCount> _computeDailyRides(List<Ride> rides) {
  // Bucket by local date so the seven labels match the user's calendar.
  final now = DateTime.now();
  final buckets = <DateTime, int>{};
  for (int i = 6; i >= 0; i--) {
    final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
    buckets[d] = 0;
  }
  for (final r in rides) {
    final ts = r.createdAt;
    if (ts == null) continue;
    final key = DateTime(ts.year, ts.month, ts.day);
    if (buckets.containsKey(key)) {
      buckets[key] = buckets[key]! + 1;
    }
  }
  final fmt = DateFormat('EEE');
  return buckets.entries
      .map((e) => _DailyRideCount(label: fmt.format(e.key), count: e.value))
      .toList();
}

class _RatingStats {
  final int total;
  final double avg;
  /// dist[0] == count of 1-star, dist[4] == count of 5-star.
  final List<int> dist;
  const _RatingStats({required this.total, required this.avg, required this.dist});
}

_RatingStats _computeRatingStats(List<Ride> rides) {
  final dist = [0, 0, 0, 0, 0];
  int sum = 0, total = 0;
  for (final r in rides) {
    final n = r.rating;
    if (n == null) continue;
    final clamped = n.clamp(AppConstants.minRating, AppConstants.maxRating);
    dist[clamped - 1]++;
    sum += clamped;
    total++;
  }
  final avg = total == 0 ? 0.0 : sum / total;
  return _RatingStats(total: total, avg: avg, dist: dist);
}

List<Ride> _computeRecentComments(List<Ride> rides) {
  final list = rides
      .where((r) => r.rating != null && (r.feedback?.isNotEmpty ?? false))
      .toList()
    ..sort((a, b) {
      final ta = a.ratedAt?.millisecondsSinceEpoch ?? 0;
      final tb = b.ratedAt?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
  return list.take(6).toList();
}

class _FeedbackStats {
  final int total, issue, suggestion, question, other, unresolved;
  const _FeedbackStats({
    required this.total,
    required this.issue,
    required this.suggestion,
    required this.question,
    required this.other,
    required this.unresolved,
  });
}

_FeedbackStats _computeFeedbackStats(List<FeedbackEntry> entries) {
  int i = 0, s = 0, q = 0, o = 0, u = 0;
  for (final f in entries) {
    switch (f.category) {
      case FeedbackCategory.issue:
        i++;
        break;
      case FeedbackCategory.suggestion:
        s++;
        break;
      case FeedbackCategory.question:
        q++;
        break;
      case FeedbackCategory.other:
        o++;
        break;
    }
    if (!f.resolved) u++;
  }
  return _FeedbackStats(
    total: entries.length,
    issue: i,
    suggestion: s,
    question: q,
    other: o,
    unresolved: u,
  );
}

class _TopDriverRow {
  final String email;
  final String displayName;
  final int count;
  const _TopDriverRow({
    required this.email,
    required this.displayName,
    required this.count,
  });
}

List<_TopDriverRow> _computeTopDrivers(
    List<Ride> rides, List<Driver> drivers) {
  final counts = <String, int>{};
  for (final r in rides) {
    if (r.status != RideStatus.completed) continue;
    final email = r.assignedDriver;
    if (email == null) continue;
    final norm = normalizeEmail(email);
    counts[norm] = (counts[norm] ?? 0) + 1;
  }
  final entries = counts.entries.map((e) {
    final d = drivers.firstWhere(
      (drv) => drv.email == e.key,
      orElse: () => Driver(
        email: e.key,
        firstName: '',
        lastName: '',
        phone: '',
        plateNumber: '',
        status: DriverStatus.unknown,
      ),
    );
    final name = d.fullName.isEmpty ? e.key : d.fullName;
    return _TopDriverRow(email: e.key, displayName: name, count: e.value);
  }).toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return entries.take(5).toList();
}

// ── Widgets ──────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _StatItem {
  final Color color;
  final String number;
  final String label;
  const _StatItem(this.color, this.number, this.label);
}

class _StatGrid extends StatelessWidget {
  final List<_StatItem> items;
  const _StatGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Auto-fill columns at min ~140 logical px each.
        final cols = (c.maxWidth / 150).floor().clamp(2, 4);
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.7,
          children: items.map((it) => _StatTile(item: it)).toList(),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final _StatItem item;
  const _StatTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: item.color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.number,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: item.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DailyBarChart extends StatelessWidget {
  final List<_DailyRideCount> days;
  const _DailyBarChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final maxDaily = days.fold<int>(1, (m, d) => d.count > m ? d.count : m);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (final d in days)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      d.label,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: d.count / maxDaily,
                        minHeight: 16,
                        backgroundColor: AppColors.background,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${d.count}',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RatingBlock extends StatelessWidget {
  final _RatingStats stats;
  const _RatingBlock({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'No ratings submitted yet.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                stats.avg.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '/ 5.00',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
              ),
              const Spacer(),
              Text(
                'from ${stats.total} rating${stats.total == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final star in const [5, 4, 3, 2, 1])
            _StarBarRow(
              star: star,
              count: stats.dist[star - 1],
              total: stats.total,
            ),
        ],
      ),
    );
  }
}

class _StarBarRow extends StatelessWidget {
  final int star;
  final int count;
  final int total;
  const _StarBarRow(
      {required this.star, required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    final color = star >= 4
        ? AppColors.success
        : star == 3
            ? AppColors.warning
            : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '$star',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(width: 2),
                Icon(Icons.star_rounded, size: 12, color: color),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 14,
                backgroundColor: AppColors.background,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text(
              '$count',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  final Ride ride;
  const _CommentCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    final r = ride.rating ?? 0;
    final color = r >= 4
        ? AppColors.success
        : r == 3
            ? AppColors.warning
            : AppColors.danger;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (int i = 1; i <= 5; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    i <= r ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 14,
                    color: i <= r ? AppColors.accent : AppColors.surfaceAlt,
                  ),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ride.commuter.isEmpty ? 'Commuter' : ride.commuter,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ride.feedback ?? '',
            style: const TextStyle(
                color: AppColors.text, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final FeedbackEntry entry;
  const _FeedbackCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (entry.category) {
      FeedbackCategory.issue =>
        (LucideIcons.alertTriangle, AppColors.danger, 'ISSUE'),
      FeedbackCategory.suggestion =>
        (LucideIcons.lightbulb, AppColors.warning, 'SUGGESTION'),
      FeedbackCategory.question =>
        (LucideIcons.helpCircle, AppColors.info, 'QUESTION'),
      FeedbackCategory.other =>
        (LucideIcons.messageCircle, AppColors.violet, 'OTHER'),
    };
    final when = entry.createdAt;
    final whenLabel = when == null
        ? null
        : DateFormat('MMM d, h:mm a').format(when);
    return Opacity(
      opacity: entry.resolved ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '· ${feedbackRoleToString(entry.role)}',
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 11),
                ),
                if (entry.resolved) ...[
                  const SizedBox(width: 6),
                  const Text(
                    '✓ resolved',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const Spacer(),
                if (whenLabel != null)
                  Text(
                    whenLabel,
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.message,
              style: const TextStyle(
                  color: AppColors.text, fontSize: 13, height: 1.5),
            ),
            if (entry.contact != null && entry.contact!.isNotEmpty) ...[
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 11),
                  children: [
                    const TextSpan(text: 'Contact: '),
                    TextSpan(
                      text: entry.contact,
                      style: TextStyle(
                          color: AppColors.text.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopDriversTable extends StatelessWidget {
  final List<_TopDriverRow> rows;
  const _TopDriversTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].displayName,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          rows[i].email,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${rows[i].count}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1)
              Container(
                height: 1,
                color: AppColors.background.withValues(alpha: 0.6),
              ),
          ],
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    );
  }
}

class _DashLoading extends StatelessWidget {
  final String message;
  const _DashLoading({required this.message});

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

class _DashAccessDenied extends ConsumerWidget {
  const _DashAccessDenied();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.xCircle, size: 40, color: AppColors.danger),
            const SizedBox(height: 12),
            const Text(
              'Access Denied',
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.arrowLeft, size: 14),
              label: const Text('Back'),
              onPressed: () => context.go('/'),
            ),
          ],
        ),
      ),
    );
  }
}
