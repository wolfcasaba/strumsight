/// Returns whether two lists contain equal elements in the same order.
bool listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Produces a structural hash for an ordered list.
int listHash<T>(List<T> values) => Object.hashAll(values);

/// Returns whether two maps contain the same key-value pairs.
bool mapEquals<K, V>(Map<K, V> left, Map<K, V> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// Produces an insertion-order-independent structural hash for a map.
int mapHash<K, V>(Map<K, V> values) => Object.hashAllUnordered(
  values.entries.map((entry) => Object.hash(entry.key, entry.value)),
);
