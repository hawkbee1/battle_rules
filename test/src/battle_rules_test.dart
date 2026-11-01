// A runtime instance, so coverage sees the constructor run.
// ignore_for_file: prefer_const_constructors
import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

void main() {
  group(BattleRules, () {
    test('can be instantiated', () {
      expect(BattleRules(), isA<BattleRules>());
    });
  });
}
