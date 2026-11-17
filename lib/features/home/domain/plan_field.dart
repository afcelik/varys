/// Explicit state of a field in a partial (PUT) daily plan update.
///
/// A nullable parameter cannot tell "not passed" from "passed null", so
/// partial updates use this type instead:
/// - [PlanField.unset]: field is not sent (server keeps the current value)
/// - [PlanField.set]: field is sent with a value
/// - [PlanField.clear]: field is sent as explicit `null` (server clears it)
sealed class PlanField<T> {
  const PlanField();

  const factory PlanField.unset() = PlanFieldUnset<T>;
  const factory PlanField.set(T value) = PlanFieldSet<T>;
  const factory PlanField.clear() = PlanFieldClear<T>;

  bool get isUnset => this is PlanFieldUnset<T>;

  /// Writes this field into [body] under [key]:
  /// set → value, clear → explicit null, unset → nothing.
  void writeTo(Map<String, dynamic> body, String key) {
    switch (this) {
      case PlanFieldUnset<T>():
        break;
      case PlanFieldSet<T>(:final value):
        body[key] = value;
      case PlanFieldClear<T>():
        body[key] = null;
    }
  }
}

final class PlanFieldUnset<T> extends PlanField<T> {
  const PlanFieldUnset();

  @override
  bool operator ==(Object other) => other is PlanFieldUnset<T>;

  @override
  int get hashCode => Object.hash(PlanFieldUnset, T);

  @override
  String toString() => 'PlanField.unset()';
}

final class PlanFieldSet<T> extends PlanField<T> {
  const PlanFieldSet(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is PlanFieldSet<T> && other.value == value;

  @override
  int get hashCode => Object.hash(PlanFieldSet, T, value);

  @override
  String toString() => 'PlanField.set($value)';
}

final class PlanFieldClear<T> extends PlanField<T> {
  const PlanFieldClear();

  @override
  bool operator ==(Object other) => other is PlanFieldClear<T>;

  @override
  int get hashCode => Object.hash(PlanFieldClear, T);

  @override
  String toString() => 'PlanField.clear()';
}
