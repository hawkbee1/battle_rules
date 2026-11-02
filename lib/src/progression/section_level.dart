import 'package:battle_rules/src/data/units_data.dart';

/// {@template section_level}
/// What a section's XP gives (UNIT-15, UNIT-17, UNIT-39, UNIT-40): its
/// commander's level, and from the level the section size cap and the
/// number of units the section may own.
/// {@endtemplate}
final class SectionLevel {
  /// {@macro section_level}
  const new(this.progression);

  /// The `progression` of `units.yaml`.
  final Progression progression;

  /// The commander level of a section with [sectionXp]: the number of
  /// `commander_levels.section_xp` thresholds it has reached, from 1 to
  /// `max_level` (UNIT-15, UNIT-17).
  int levelFor(double sectionXp) {
    final reached = progression.commanderLevels.sectionXp
        .where((threshold) => threshold <= sectionXp)
        .length;
    return reached < 1 ? 1 : reached;
  }

  /// The section size cap at commander [level]: the active units, the
  /// commander included (UNIT-39, decision 127).
  int cap(int level) {
    final size = progression.sectionSize;
    return size.capAtLevel1 + (level - 1) ~/ size.extraUnitEveryLevels;
  }

  /// The units a section may own at commander [level], active and stored:
  /// `max_units_factor` × [cap] (UNIT-40). Its storage holds as many.
  int maxUnits(int level) =>
      progression.sectionSize.maxUnitsFactor * cap(level);

  /// Whether a section at commander [level] with [active] units on the
  /// field and [owned] units in all has room for one more (ECO-04,
  /// decision 130): a bought unit arrives on the field, so both the cap
  /// (UNIT-39) and the units owned (UNIT-40) must leave room.
  bool hasRoom({required int level, required int active, required int owned}) =>
      active < cap(level) && owned < maxUnits(level);
}
