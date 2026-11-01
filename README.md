# battle_rules

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

The headless **rules core** of Battle Team, a 3D, massive, persistent, real-time team
battle game: AP, movement cost, vision and combat resolution, exactly as the game
specification says. The simulation host and the client both use it, so the rules
change in one place.

- **Pure Dart**: no Flutter, no rendering, no network.
- **No I/O in `lib/`**: the caller passes the YAML text of the game data, maps and
  time. Only command-line tools in `bin/` may read files.
- **Deterministic**: time comes from an injected clock or as an argument, randomness
  from an injected seeded generator.
- **No game number in code**: every number comes from the game data files.

## Part of hawkbee

This repository is a git submodule of the
[hawkbee](https://github.com/hawkbee1/hawkbee) monorepo and **only builds inside
it** (pub workspace, `resolution: workspace`). Its tests also read the game data
from the hawkbee checkout:

```sh
git clone --recurse-submodules https://github.com/hawkbee1/hawkbee.git
cd hawkbee && flutter pub get
```

## Game data

`GameData.parse` takes the text of the six game data files and returns typed,
immutable models. It checks the types, the required keys and the rules between
values, and throws a `GameDataException` naming the file, the key and the value
of the first problem:

```dart
final data = GameData.parse(
  units: unitsYaml,
  combat: combatYaml,
  terrain: terrainYaml,
  battle: battleYaml,
  economy: economyYaml,
  medals: medalsYaml,
);
final rifle = data.combat.weaponTypes['rifle'];
```

The caller reads the files. `economy.yaml` lives in `plan/milestones/`, the
other five in `plan/data/`.

## Specification

The rules live in the Battle Team app repository, mounted in hawkbee at
`apps/battle_team/plan/`:

| Path | Content |
|---|---|
| [`plan/milestones/m4-rules-core.md`](https://github.com/hawkbee1/battle_team/blob/main/plan/milestones/m4-rules-core.md) | The milestone this package implements, one issue per work session. |
| [`plan/specs/`](https://github.com/hawkbee1/battle_team/tree/main/plan/specs) | The rules, each with a stable ID (`COMBAT-06`, `MAP-15`, ...). Code and tests cite these IDs. |
| [`plan/data/`](https://github.com/hawkbee1/battle_team/tree/main/plan/data) | Every number of the game. Tests on real values read these files through `test/helpers/plan_data.dart`. |
| [`plan/stack/07-engineering-principles.md`](https://github.com/hawkbee1/battle_team/blob/main/plan/stack/07-engineering-principles.md) | Principles, patterns and package layout. |

Work sessions: hawkbee's [docs/battle_team](https://github.com/hawkbee1/hawkbee/tree/main/docs/battle_team).

## Running tests

From the package folder, inside a hawkbee checkout:

```sh
very_good test --coverage
```

The target is 100 % line coverage. Static analysis:

```sh
dart analyze --fatal-infos
```

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
