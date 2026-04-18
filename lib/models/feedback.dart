import 'package:cloud_firestore/cloud_firestore.dart';

/// Categories must match the Firestore validator exactly.
enum FeedbackCategory { issue, suggestion, question, other }

FeedbackCategory feedbackCategoryFromString(String? raw) {
  switch (raw) {
    case 'issue':
      return FeedbackCategory.issue;
    case 'suggestion':
      return FeedbackCategory.suggestion;
    case 'question':
      return FeedbackCategory.question;
    default:
      return FeedbackCategory.other;
  }
}

String feedbackCategoryToString(FeedbackCategory c) => c.name;

enum FeedbackRole { commuter, driver, anonymous }

FeedbackRole feedbackRoleFromString(String? raw) {
  switch (raw) {
    case 'commuter':
      return FeedbackRole.commuter;
    case 'driver':
      return FeedbackRole.driver;
    default:
      return FeedbackRole.anonymous;
  }
}

String feedbackRoleToString(FeedbackRole r) => r.name;

class FeedbackEntry {
  final String id;
  final FeedbackCategory category;
  final FeedbackRole role;
  final String message;
  final String? contact;
  final bool resolved;
  final DateTime? createdAt;

  const FeedbackEntry({
    required this.id,
    required this.category,
    required this.role,
    required this.message,
    this.contact,
    this.resolved = false,
    this.createdAt,
  });

  factory FeedbackEntry.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return FeedbackEntry(
      id: doc.id,
      category: feedbackCategoryFromString(d['category'] as String?),
      role: feedbackRoleFromString(d['role'] as String?),
      message: (d['message'] as String?) ?? '',
      contact: d['contact'] as String?,
      resolved: (d['resolved'] as bool?) ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'category': feedbackCategoryToString(category),
        'role': feedbackRoleToString(role),
        'message': message,
        if (contact != null && contact!.isNotEmpty) 'contact': contact,
        'resolved': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
