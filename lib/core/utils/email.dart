/// Normalise an email for use as a Firestore document ID.
///
/// Firestore IDs are case-sensitive and the security rules compare the
/// authenticated email to the doc ID. We always lowercase + trim on
/// every read, write, and rule check so that "Driver@Foo.com" and
/// "driver@foo.com" can never end up with two separate driver docs.
String normalizeEmail(String email) => email.trim().toLowerCase();
