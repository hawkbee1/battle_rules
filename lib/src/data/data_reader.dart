import 'package:battle_rules/src/data/game_data_exception.dart';
import 'package:yaml/yaml.dart';

/// {@template data_reader}
/// Reads typed values from one map of a parsed game data file.
///
/// Every problem is thrown as a [GameDataException] naming the [file], the
/// key path and the value. Absent and null optional values read as null.
/// {@endtemplate}
final class DataReader {
  /// {@macro data_reader}
  const new(this.file, this.path, this._map);

  /// Parses [text], the content of [file]. Its top level must be a map.
  factory parse(String file, String text) {
    final Object? root;
    try {
      root = loadYaml(text);
    } on YamlException catch (error) {
      throw GameDataException(
        file: file,
        key: '',
        value: null,
        problem: 'invalid YAML: ${error.message}',
      );
    }
    if (root is! Map) {
      throw GameDataException(
        file: file,
        key: '',
        value: root,
        problem: 'the document must be a map',
      );
    }
    return DataReader(file, '', root);
  }

  /// The data file, for example `units.yaml`.
  final String file;

  /// The dotted key path of this map in [file]; empty at the top level.
  final String path;

  final Map<Object?, Object?> _map;

  /// The keys of this map, in file order.
  Iterable<String> get keys => _map.keys.map((key) => '$key');

  /// Whether this map has [key], even with a null value.
  bool has(String key) => _map.containsKey(key);

  /// The full dotted path of [key] in this map.
  String keyPath(String key) => path.isEmpty ? key : '$path.$key';

  /// Throws a [GameDataException] for the [value] of [key] in this map.
  Never fail(String key, Object? value, String problem) =>
      throw GameDataException(
        file: file,
        key: keyPath(key),
        value: value,
        problem: problem,
      );

  Object? _required(String key) {
    if (!has(key)) fail(key, null, 'missing');
    return _map[key];
  }

  bool _isAbsent(String key) => _map[key] == null;

  /// The map at [key].
  DataReader map(String key) {
    final value = _required(key);
    if (value is! Map) fail(key, value, 'must be a map');
    return DataReader(file, keyPath(key), value);
  }

  /// The map at [key], or null when it is absent.
  DataReader? optionalMap(String key) => _isAbsent(key) ? null : map(key);

  /// Every value of this map, each read as a map, by key.
  Map<String, DataReader> maps() => {for (final key in keys) key: map(key)};

  /// The integer at [key].
  int integer(String key) {
    final value = _required(key);
    if (value is! int) fail(key, value, 'must be an integer');
    return value;
  }

  /// The number at [key]; an integer reads as a double.
  double number(String key) {
    final value = _required(key);
    if (value is! num) fail(key, value, 'must be a number');
    return value.toDouble();
  }

  /// The number at [key], or null when it is absent or null.
  double? optionalNumber(String key) => _isAbsent(key) ? null : number(key);

  /// The number at [key], which must be present but may be null.
  double? numberOrNull(String key) {
    _required(key);
    return optionalNumber(key);
  }

  /// The string at [key].
  String string(String key) {
    final value = _required(key);
    if (value is! String) fail(key, value, 'must be a string');
    return value;
  }

  /// The string at [key], or null when it is absent or null.
  String? optionalString(String key) => _isAbsent(key) ? null : string(key);

  /// The string at [key], which must be present but may be null.
  String? stringOrNull(String key) {
    _required(key);
    return optionalString(key);
  }

  /// The boolean at [key].
  bool boolean(String key) {
    final value = _required(key);
    if (value is! bool) fail(key, value, 'must be true or false');
    return value;
  }

  /// The boolean at [key], or [absent] when it is absent or null.
  bool optionalBoolean(String key, {required bool absent}) =>
      _isAbsent(key) ? absent : boolean(key);

  List<Object?> _list(String key) {
    final value = _required(key);
    if (value is! List) fail(key, value, 'must be a list');
    return value;
  }

  /// The items of the list at [key], each converted by [convert], which
  /// returns null for an item that is not [expected].
  List<T> _items<T extends Object>(
    String key,
    String expected,
    T? Function(Object? item) convert,
  ) => List.unmodifiable([
    for (final (index, item) in _list(key).indexed)
      convert(item) ?? fail('$key[$index]', item, 'must be $expected'),
  ]);

  /// The list of strings at [key].
  List<String> strings(String key) =>
      _items(key, 'a string', (item) => item is String ? item : null);

  /// The list of strings at [key], or an empty list when it is absent.
  List<String> optionalStrings(String key) =>
      _isAbsent(key) ? const [] : strings(key);

  /// The list of integers at [key].
  List<int> integers(String key) =>
      _items(key, 'an integer', (item) => item is int ? item : null);

  /// The list of numbers at [key]; integers read as doubles.
  List<double> numbers(String key) =>
      _items(key, 'a number', (item) => item is num ? item.toDouble() : null);

  /// Every value of this map, each read as an integer, by key.
  Map<String, int> integerEntries() =>
      Map.unmodifiable({for (final key in keys) key: integer(key)});

  /// Every value of this map, each read as a number, by key.
  Map<String, double> numberEntries() =>
      Map.unmodifiable({for (final key in keys) key: number(key)});

  /// Every value of this map, each read as a number or null, by key.
  Map<String, double?> numberOrNullEntries() =>
      Map.unmodifiable({for (final key in keys) key: numberOrNull(key)});
}
