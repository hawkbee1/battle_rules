/// {@template game_data_exception}
/// A game data file that cannot be used: bad YAML, a missing key, a value of
/// the wrong type, or a value that breaks a rule between values.
///
/// The message names the [file], the [key] and the [value].
/// {@endtemplate}
final class GameDataException implements Exception {
  /// {@macro game_data_exception}
  const new({
    required this.file,
    required this.key,
    required this.value,
    required this.problem,
  });

  /// The data file, for example `units.yaml`.
  final String file;

  /// The dotted path of the key in [file], for example
  /// `units.radio.weapons.default`. Empty when the problem is the whole
  /// document.
  final String key;

  /// The value found at [key]; null when the key is missing.
  final Object? value;

  /// What is wrong with [value].
  final String problem;

  @override
  String toString() {
    final shown = value is String ? '"$value"' : '$value';
    return key.isEmpty
        ? 'GameDataException: $file: $problem'
        : 'GameDataException: $file: $key = $shown: $problem';
  }
}
