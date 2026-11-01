import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

void main() {
  group(GameDataException, () {
    test('names the file, the key and a quoted string value', () {
      const error = GameDataException(
        file: 'units.yaml',
        key: 'units.radio.weapons.default',
        value: 'laser',
        problem: 'not in its allowed list []',
      );

      expect(
        error.toString(),
        'GameDataException: units.yaml: units.radio.weapons.default = '
        '"laser": not in its allowed list []',
      );
    });

    test('shows a number or a missing value as it is', () {
      const missing = GameDataException(
        file: 'battle.yaml',
        key: 'ap.max',
        value: null,
        problem: 'missing',
      );
      const number = GameDataException(
        file: 'battle.yaml',
        key: 'ap.max',
        value: 2.5,
        problem: 'too low',
      );

      expect(
        missing.toString(),
        'GameDataException: battle.yaml: ap.max = null: missing',
      );
      expect(
        number.toString(),
        'GameDataException: battle.yaml: ap.max = 2.5: too low',
      );
    });

    test('names only the file when the problem is the whole document', () {
      const error = GameDataException(
        file: 'medals.yaml',
        key: '',
        value: null,
        problem: 'the document must be a map',
      );

      expect(
        error.toString(),
        'GameDataException: medals.yaml: the document must be a map',
      );
    });
  });
}
