import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/ride.dart';
import '../../providers/auth_provider.dart';
import '../../providers/presence_provider.dart';
import '../../providers/rides_provider.dart';
import '../../widgets/primary_button.dart';
import 'commuter_accepted_view.dart';
import 'commuter_rating_view.dart';
import 'commuter_scheduled_view.dart';
import 'commuter_searching_view.dart';

/// Phases the booking flow can be in. The screen is a state machine
/// driven by (a) form submission and (b) the live ride doc snapshot.
enum BookingPhase {
  form,
  searching,
  scheduled,
  accepted,
  rating,
  done,
}

class CommuterBookingScreen extends ConsumerStatefulWidget {
  const CommuterBookingScreen({super.key});

  @override
  ConsumerState<CommuterBookingScreen> createState() =>
      _CommuterBookingScreenState();
}

class _CommuterBookingScreenState extends ConsumerState<CommuterBookingScreen> {
  BookingPhase _phase = BookingPhase.form;
  String? _rideId;

  /// Cached so the searching/scheduled views can show the route summary
  /// before the first Firestore snapshot arrives.
  String _summaryPickup = '';
  String _summaryDropoff = '';
  DateTime? _scheduledFor;

  /// Locks user actions during async submits.
  bool _busy = false;

  void _toForm() {
    setState(() {
      _phase = BookingPhase.form;
      _rideId = null;
      _scheduledFor = null;
    });
  }

  Future<void> _onRideCreated({
    required String rideId,
    required String pickup,
    required String dropoff,
    required DateTime? scheduledFor,
  }) async {
    setState(() {
      _rideId = rideId;
      _summaryPickup = pickup;
      _summaryDropoff = dropoff;
      _scheduledFor = scheduledFor;
      _phase = scheduledFor != null
          ? BookingPhase.scheduled
          : BookingPhase.searching;
    });
  }

  /// Reacts to live updates from the ride doc and advances the phase.
  void _applyRideUpdate(Ride ride) {
    switch (ride.status) {
      case RideStatus.searching:
        // Either the initial searching state OR a scheduled ride still
        // waiting to enter the queue. We keep whatever sub-phase the
        // user is already in (scheduled vs searching) — both are
        // visually correct for `searching`.
        return;
      case RideStatus.accepted:
      case RideStatus.inTransit:
        // Both states reuse the accepted phase view (live map). The
        // view itself reads ride.status to swap its header copy and
        // hide the cancel button once the commuter is onboard.
        if (_phase != BookingPhase.accepted) {
          setState(() => _phase = BookingPhase.accepted);
        }
        return;
      case RideStatus.completed:
        if (_phase != BookingPhase.rating && _phase != BookingPhase.done) {
          setState(() => _phase = BookingPhase.rating);
        }
        return;
      case RideStatus.cancelled:
        // Could be cancelled by us OR by the assigned driver. Either
        // way, drop back to the form so they can rebook.
        if (_phase != BookingPhase.form) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ride was cancelled.'),
          ));
          _toForm();
        }
        return;
      case RideStatus.unknown:
        return;
    }
  }

  Future<void> _cancelRide() async {
    final id = _rideId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(firestoreServiceProvider).cancelRide(id);
      // Optimistically reset — listener will reconfirm.
      _toForm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to the ride doc once we have an ID. Watching here keeps
    // the StreamProvider alive across phase changes inside this screen.
    if (_rideId != null) {
      ref.listen<AsyncValue<Ride>>(rideStreamProvider(_rideId!),
          (prev, next) {
        next.whenData(_applyRideUpdate);
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.go('/'),
        ),
        title: Text(_titleForPhase()),
      ),
      body: SafeArea(child: _bodyForPhase()),
    );
  }

  String _titleForPhase() {
    switch (_phase) {
      case BookingPhase.form:
        return 'Book a ride';
      case BookingPhase.searching:
        return 'Looking for a driver';
      case BookingPhase.scheduled:
        return 'Ride scheduled';
      case BookingPhase.accepted:
        // Same phase covers `accepted` (driver en route) and
        // `in_transit` (passenger onboard). The accepted view tweaks
        // its body copy; the title here stays generic to cover both.
        return 'On your trip';
      case BookingPhase.rating:
        return 'Rate your trip';
      case BookingPhase.done:
        return 'All set';
    }
  }

  Widget _bodyForPhase() {
    switch (_phase) {
      case BookingPhase.form:
        return _BookingForm(
          onCreated: _onRideCreated,
        );
      case BookingPhase.searching:
        return CommuterSearchingView(
          pickup: _summaryPickup,
          dropoff: _summaryDropoff,
          busy: _busy,
          onCancel: _cancelRide,
        );
      case BookingPhase.scheduled:
        return CommuterScheduledView(
          pickup: _summaryPickup,
          dropoff: _summaryDropoff,
          scheduledFor: _scheduledFor!,
          busy: _busy,
          onCancel: _cancelRide,
        );
      case BookingPhase.accepted:
        return CommuterAcceptedView(rideId: _rideId!);
      case BookingPhase.rating:
        return CommuterRatingView(
          rideId: _rideId!,
          onDone: () => setState(() => _phase = BookingPhase.done),
        );
      case BookingPhase.done:
        return _DoneView(onBookAnother: _toForm);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Form view
// ──────────────────────────────────────────────────────────────────────────

class _BookingForm extends ConsumerStatefulWidget {
  final Future<void> Function({
    required String rideId,
    required String pickup,
    required String dropoff,
    required DateTime? scheduledFor,
  }) onCreated;

  const _BookingForm({required this.onCreated});

  @override
  ConsumerState<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends ConsumerState<_BookingForm> {
  final _formKey = GlobalKey<FormState>();
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  final _notes = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  bool _scheduled = false;
  DateTime? _date;
  TimeOfDay? _time;

  bool _submitting = false;
  GeoCoords? _capturedPickupCoords;

  @override
  void initState() {
    super.initState();
    _attemptInitialFix();
  }

  /// Best-effort GPS capture — the form is submittable without it.
  Future<void> _attemptInitialFix() async {
    final loc = ref.read(locationServiceProvider);
    final pos = await loc.currentPosition();
    if (!mounted || pos == null) return;
    setState(() {
      _capturedPickupCoords = GeoCoords(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
      );
    });
  }

  @override
  void dispose() {
    for (final c in [_pickup, _dropoff, _notes, _name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? get _combinedScheduledFor {
    if (!_scheduled || _date == null || _time == null) return null;
    return DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
  }

  String? _validateScheduled() {
    if (!_scheduled) return null;
    final dt = _combinedScheduledFor;
    if (dt == null) return 'Pick a date and time';

    final now = DateTime.now();
    final minAt = now.add(AppConstants.minScheduleAhead);
    final maxAt = now.add(AppConstants.maxScheduleAhead);
    if (dt.isBefore(minAt)) {
      return 'Schedule at least 5 minutes from now';
    }
    if (dt.isAfter(maxAt)) {
      return 'Schedule no more than 7 days from now';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(AppConstants.maxScheduleAhead),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.surface,
              onSurface: AppColors.text,
              onPrimary: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.surface,
              onSurface: AppColors.text,
              onPrimary: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final scheduleError = _validateScheduled();
    if (scheduleError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(scheduleError)),
      );
      return;
    }

    setState(() => _submitting = true);
    final scheduledFor = _combinedScheduledFor;
    final ride = Ride(
      id: '',
      pickup: _pickup.text.trim(),
      dropoff: _dropoff.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      commuter: _name.text.trim(),
      commuterPhone: _phone.text.trim(),
      status: RideStatus.searching,
      pickupCoords: _capturedPickupCoords,
      scheduledFor: scheduledFor,
    );

    try {
      final ref0 = await ref.read(firestoreServiceProvider).createRide(ride);
      if (!mounted) return;
      await widget.onCreated(
        rideId: ref0.id,
        pickup: ride.pickup,
        dropoff: ride.dropoff,
        scheduledFor: scheduledFor,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create ride: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _required(String? v, String label) =>
      (v ?? '').trim().isEmpty ? '$label is required' : null;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(
              icon: LucideIcons.mapPin,
              title: 'Where to?',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pickup,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Pickup',
                hintText: 'e.g. Block 12, Phase 2',
                prefixIcon: Icon(LucideIcons.circleDot, size: 18),
              ),
              validator: (v) => _required(v, 'Pickup'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dropoff,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Drop-off',
                hintText: 'e.g. Castillejos Public Market',
                prefixIcon: Icon(LucideIcons.flag, size: 18),
              ),
              validator: (v) => _required(v, 'Drop-off'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              maxLength: 200,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Notes for driver (optional)',
                hintText: 'Carrying groceries, with elderly passenger, …',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 28),
                  child: Icon(LucideIcons.stickyNote, size: 18),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionHeader(
              icon: LucideIcons.user,
              title: 'Your details',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(LucideIcons.user, size: 18),
              ),
              validator: (v) => _required(v, 'Name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: const InputDecoration(
                labelText: 'Phone',
                hintText: 'So the driver can reach you',
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
            const SizedBox(height: 20),
            _ScheduleToggle(
              value: _scheduled,
              date: _date,
              time: _time,
              onToggle: (v) => setState(() {
                _scheduled = v;
                if (!v) {
                  _date = null;
                  _time = null;
                }
              }),
              onPickDate: _pickDate,
              onPickTime: _pickTime,
            ),
            if (_capturedPickupCoords != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(LucideIcons.mapPin,
                      size: 14, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text(
                    'Got your current location for the matcher',
                    style: TextStyle(
                      color: AppColors.success.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            PrimaryButton(
              label: _scheduled ? 'Schedule ride' : 'Find me a driver',
              icon: _scheduled ? LucideIcons.calendar : LucideIcons.search,
              busy: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleToggle extends StatelessWidget {
  final bool value;
  final DateTime? date;
  final TimeOfDay? time;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  const _ScheduleToggle({
    required this.value,
    required this.date,
    required this.time,
    required this.onToggle,
    required this.onPickDate,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceAlt),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(LucideIcons.calendar,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Schedule for later',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Switch.adaptive(
                value: value,
                activeThumbColor: AppColors.accent,
                onChanged: onToggle,
              ),
            ],
          ),
          if (value) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickDate,
                    icon: const Icon(LucideIcons.calendar, size: 16),
                    label: Text(date == null
                        ? 'Pick date'
                        : '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: BorderSide(
                          color: AppColors.muted.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickTime,
                    icon: const Icon(LucideIcons.clock, size: 16),
                    label: Text(time == null
                        ? 'Pick time'
                        : time!.format(context)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: BorderSide(
                          color: AppColors.muted.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Between 5 minutes and 7 days from now.',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Done view (after rating)
// ──────────────────────────────────────────────────────────────────────────

class _DoneView extends StatelessWidget {
  final VoidCallback onBookAnother;
  const _DoneView({required this.onBookAnother});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.check,
                size: 56, color: AppColors.success),
          ),
          const SizedBox(height: 20),
          const Text(
            'Thank you!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your feedback helps the next commuter and driver.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const Spacer(),
          PrimaryButton(
            label: 'Book another ride',
            icon: LucideIcons.plus,
            onPressed: onBookAnother,
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Back to home',
            icon: LucideIcons.home,
            onPressed: () => context.go('/'),
          ),
        ],
      ),
    );
  }
}
