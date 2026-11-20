/// Turkish-aware text helpers shared by features (task search, notes).
///
/// Moved here from `features/home/domain/addable_tasks.dart`, which still
/// re-exports [turkishLower] and [matchesQuery] for its existing users.
library;

/// Turkish-aware lowercase: İ → i and I → ı, then the default lowercase.
String turkishLower(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// Case-insensitive (Turkish-aware) substring match. An empty query matches all.
bool matchesQuery(String title, String query) {
  final q = turkishLower(query.trim());
  if (q.isEmpty) return true;
  return turkishLower(title).contains(q);
}
