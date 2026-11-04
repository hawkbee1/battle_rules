import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

void main() {
  group(TerrainData, () {
    late TerrainData terrain;

    setUp(() {
      terrain = TerrainData.parse(readFixture('terrain.yaml'));
    });

    test('reads the version, movement classes and flying limit', () {
      expect(terrain.version, 2);
      expect(terrain.movementClasses, ['foot', 'wheeled', 'tracked']);
      expect(terrain.flyingMaxAboveHighestTerrainM, 15);
    });

    test('MAP-15 lists the movement classes, then the profiles', () {
      expect(terrain.movementModes, [
        'foot',
        'wheeled',
        'tracked',
        'flying',
        'sail',
        'push',
      ]);
    });

    test('MAP-21 reads the slope row of each class and profile', () {
      final wheeled = terrain.slope['wheeled']!;

      expect(terrain.slope.keys, terrain.movementModes);
      expect(wheeled.factor, 0.08);
      expect(wheeled.maxDegrees, 20);
      expect(wheeled.minMultiplier, 0.6);
    });

    test('MAP-35 reads the vision, weather and terrain vision values', () {
      expect(terrain.vision.heightBonusMPerM, 1.5);
      expect(terrain.vision.heightBonusMaxM, 100);
      expect(terrain.vision.forestVisionCostPerM, 3);
      expect(terrain.vision.destroyedObjectsBlock, isFalse);
      expect(terrain.weather, {'clear': 1.0, 'fog': 0.5});
      expect(terrain.terrainTypes['island']!.visionFactor, 0.9);
    });

    test('MAP-15 reads AP multipliers, null meaning impassable', () {
      final mountain = terrain.terrainTypes['mountain']!;

      expect(mountain.id, 'mountain');
      expect(mountain.blocksLos, isTrue);
      expect(mountain.apMultiplier['foot'], 2.5);
      expect(mountain.apMultiplier.containsKey('wheeled'), isTrue);
      expect(mountain.apMultiplier['wheeled'], isNull);
      expect(mountain.crossableBy, isEmpty);
      expect(mountain.access, isEmpty);
    });

    test('reads who can cross or reach a terrain type', () {
      expect(terrain.terrainTypes['lake']!.crossableBy, ['sail']);
      expect(terrain.terrainTypes['island']!.access, ['flying', 'ladder']);
    });

    test('reads craters', () {
      expect(terrain.craters.maxDepthM, 12);
      expect(terrain.craters.fillableByEngineers, isFalse);
      expect(terrain.craters.depthPerShotM, 1.5);
    });

    test('MAP-40 reads objects with their armor type', () {
      final tree = terrain.objects['tree']!;

      expect(tree.id, 'tree');
      expect(tree.armorType, 'structure');
      expect(tree.blocksLos, isFalse);
      expect(tree.conceals, 'forest');
      expect(tree.destructible, isTrue);
      expect(tree.hp, 80);
      expect(tree.construction, isNull);
      expect(tree.relicCrossable, isNull);
      expect(tree.hiddenFromEnemies, isFalse);
      expect(terrain.objects['trap']!.hiddenFromEnemies, isTrue);
    });

    test('COMBAT-10 reads construction AP and build time per structure', () {
      final bridge = terrain.objects['bridge']!;

      expect(bridge.construction?.builtBy, 'engineer');
      expect(bridge.construction?.ap, 9);
      expect(bridge.construction?.buildTimeS, 250);
      expect(bridge.relicCrossable, isFalse);
    });
  });
}
