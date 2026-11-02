import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

void main() {
  group('SectionLevel on the fixtures', () {
    // Fixture levels: 0, 100, 300, 600 section XP for levels 1 to 4; cap 4
    // at level 1, one more every 3 levels; owns 2 × cap.
    late SectionLevel levels;

    setUp(() {
      levels = SectionLevel(
        UnitsData.parse(readFixture('units.yaml')).progression,
      );
    });

    test('UNIT-15 UNIT-17 section XP sets the commander level', () {
      expect(levels.levelFor(0), 1);
      expect(levels.levelFor(99), 1);
      expect(levels.levelFor(100), 2);
      expect(levels.levelFor(599), 3);
      expect(levels.levelFor(600), 4);
      expect(levels.levelFor(1000000000), 4);
    });

    test('UNIT-39 the level sets the section size cap', () {
      expect([1, 3, 4].map(levels.cap), [4, 4, 5]);
    });

    test('UNIT-40 a section owns at most 2 × cap units', () {
      expect(levels.maxUnits(4), 10);
    });

    test('ECO-04 decision 130 room needs a place under the cap and under '
        'the units owned', () {
      // Level 1: cap 4, owns at most 8.
      expect(levels.hasRoom(level: 1, active: 3, owned: 7), isTrue);
      expect(levels.hasRoom(level: 1, active: 4, owned: 4), isFalse);
      expect(levels.hasRoom(level: 1, active: 1, owned: 8), isFalse);
    });
  });

  group('SectionLevel on the plan data', () {
    late SectionLevel levels;

    setUp(() => levels = SectionLevel(parsePlanData().units.progression));

    test('UNIT-39 the cap is 5 at levels 1 to 5, 6 at level 6, 16 at 60', () {
      expect([1, 5, 6, 10, 11, 60].map(levels.cap), [5, 5, 6, 6, 7, 16]);
    });

    test('UNIT-40 a section at its cap owns at most 2 × cap units', () {
      expect(levels.maxUnits(1), 10);
      expect(levels.maxUnits(60), 32);
    });

    test('UNIT-17 the plan levels go from 1 to 60', () {
      expect(levels.levelFor(0), 1);
      expect(levels.levelFor(499), 1);
      expect(levels.levelFor(500), 2);
      expect(levels.levelFor(885000), 60);
      expect(levels.levelFor(1000000000000), 60);
    });
  });
}
