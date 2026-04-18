import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/feedback.dart';
import '../providers/auth_provider.dart';
import '../widgets/primary_button.dart';

/// Public feedback / issue-report screen. Anyone — authenticated or
/// not — can submit. Mirrors the React reference: four categories,
/// three role tags, and a 1–2000 character message body.
///
/// The Firestore rule on `feedback/{auto}` enforces the same length
/// bounds and pins `resolved: false` + `createdAt: serverTimestamp`,
/// so the validation here is purely UX — never the source of truth.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  FeedbackCategory _category = FeedbackCategory.issue;
  FeedbackRole _role = FeedbackRole.commuter;

  final _message = TextEditingController();
  final _contact = TextEditingController();

  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final msg = _message.text.trim();
    if (msg.length < AppConstants.feedbackMinChars) {
      setState(() => _error = 'Please write a short message before sending.');
      return;
    }
    if (msg.length > AppConstants.feedbackMaxChars) {
      setState(() => _error =
          'Message is too long. Please keep it under ${AppConstants.feedbackMaxChars} characters.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final entry = FeedbackEntry(
        id: '',
        category: _category,
        role: _role,
        message: msg,
        contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
      );
      await ref.read(firestoreServiceProvider).createFeedback(entry);
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          'Could not submit. Please check your connection and try again. ($e)');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          'Feedback & Support',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: _submitted ? const _SuccessView() : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final remaining = AppConstants.feedbackMaxChars - _message.text.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel(text: 'What would you like to tell us?'),
          const SizedBox(height: 10),
          _CategoryGrid(
            value: _category,
            onChanged: _submitting
                ? null
                : (c) => setState(() => _category = c),
          ),
          const SizedBox(height: 18),
          const _SectionLabel(text: 'I am a…'),
          const SizedBox(height: 10),
          _RoleRow(
            value: _role,
            onChanged: _submitting
                ? null
                : (r) => setState(() => _role = r),
          ),
          const SizedBox(height: 18),
          const _SectionLabel(text: 'Your message'),
          const SizedBox(height: 8),
          TextField(
            controller: _message,
            maxLines: 6,
            maxLength: AppConstants.feedbackMaxChars,
            enabled: !_submitting,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText:
                  'Tell us what happened, what could be better, or ask a question…',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$remaining characters remaining',
                style: TextStyle(
                  color: AppColors.muted.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _SectionLabel(text: 'Contact (optional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _contact,
            enabled: !_submitting,
            decoration: const InputDecoration(
              hintText: "Email or phone if you'd like a reply",
              prefixIcon: Icon(LucideIcons.atSign, size: 18),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.alertTriangle,
                      size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Send feedback',
            icon: LucideIcons.send,
            busy: _submitting,
            onPressed: _submit,
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Back',
            icon: LucideIcons.arrowLeft,
            onPressed: _submitting ? null : () => context.go('/'),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Your feedback helps the next commuter and driver.',
              style: TextStyle(
                color: AppColors.muted.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ──────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  final FeedbackCategory value;
  final ValueChanged<FeedbackCategory>? onChanged;

  const _CategoryGrid({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = <_CategoryItem>[
      _CategoryItem(
        category: FeedbackCategory.issue,
        label: 'Report an issue',
        icon: LucideIcons.alertTriangle,
        color: AppColors.danger,
      ),
      _CategoryItem(
        category: FeedbackCategory.suggestion,
        label: 'Share a suggestion',
        icon: LucideIcons.lightbulb,
        color: AppColors.warning,
      ),
      _CategoryItem(
        category: FeedbackCategory.question,
        label: 'Ask a question',
        icon: LucideIcons.helpCircle,
        color: AppColors.info,
      ),
      _CategoryItem(
        category: FeedbackCategory.other,
        label: 'Other',
        icon: LucideIcons.messageCircle,
        color: AppColors.violet,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: [
        for (final item in items)
          _CategoryTile(
            item: item,
            selected: item.category == value,
            onTap: onChanged == null ? null : () => onChanged!(item.category),
          ),
      ],
    );
  }
}

class _CategoryItem {
  final FeedbackCategory category;
  final String label;
  final IconData icon;
  final Color color;
  const _CategoryItem({
    required this.category,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _CategoryTile extends StatelessWidget {
  final _CategoryItem item;
  final bool selected;
  final VoidCallback? onTap;

  const _CategoryTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = item.color;
    final border = selected
        ? accent
        : AppColors.muted.withValues(alpha: 0.25);
    final fill = selected
        ? accent.withValues(alpha: 0.15)
        : AppColors.surface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: selected ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Icon(item.icon,
                size: 18,
                color: selected ? accent : AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: selected ? accent : AppColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleRow extends StatelessWidget {
  final FeedbackRole value;
  final ValueChanged<FeedbackRole>? onChanged;

  const _RoleRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final r in FeedbackRole.values) ...[
          Expanded(
            child: _RoleButton(
              label: _label(r),
              selected: r == value,
              onTap: onChanged == null ? null : () => onChanged!(r),
            ),
          ),
          if (r != FeedbackRole.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  String _label(FeedbackRole r) {
    switch (r) {
      case FeedbackRole.commuter:
        return 'Commuter';
      case FeedbackRole.driver:
        return 'Driver';
      case FeedbackRole.anonymous:
        return 'Anonymous';
    }
  }
}

class _RoleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _RoleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accent
                : AppColors.muted.withValues(alpha: 0.25),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : AppColors.muted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.checkCheck,
                size: 56, color: AppColors.success),
          ),
          const SizedBox(height: 20),
          const Text(
            'Thank you!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your feedback has been received.\n'
            'We review every message to improve TrikeKoTo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const Spacer(),
          PrimaryButton(
            label: 'Back to home',
            icon: LucideIcons.home,
            onPressed: () => context.go('/'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
