import 'dart:io';

import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

/// Reads the fixture [file] from `test/fixtures/`, with each key of
/// [replace] replaced by its value.
///
/// Throws a [StateError] when a key does not occur exactly once, so a test
/// never passes on a replacement that did nothing.
String readFixture(String file, [Map<String, String> replace = const {}]) {
  var text = File('test/fixtures/$file').readAsStringSync();
  for (final MapEntry(:key, :value) in replace.entries) {
    final count = key.allMatches(text).length;
    if (count != 1) {
      throw StateError('"$key" occurs $count times in test/fixtures/$file');
    }
    text = text.replaceFirst(key, value);
  }
  return text;
}

/// Parses the six fixture files, each with its replacements.
GameData parseFixtures({
  Map<String, String> units = const {},
  Map<String, String> combat = const {},
  Map<String, String> terrain = const {},
  Map<String, String> battle = const {},
  Map<String, String> economy = const {},
  Map<String, String> medals = const {},
}) => GameData.parse(
  units: readFixture('units.yaml', units),
  combat: readFixture('combat.yaml', combat),
  terrain: readFixture('terrain.yaml', terrain),
  battle: readFixture('battle.yaml', battle),
  economy: readFixture('economy.yaml', economy),
  medals: readFixture('medals.yaml', medals),
);

/// Matches a [GameDataException] for [file], [key] and [value] whose
/// message contains [problem].
Matcher throwsDataError(
  String file,
  String key,
  Object? value,
  String problem,
) => throwsA(
  isA<GameDataException>()
      .having((error) => error.file, 'file', file)
      .having((error) => error.key, 'key', key)
      .having((error) => error.value, 'value', value)
      .having((error) => error.toString(), 'message', contains(problem)),
);
