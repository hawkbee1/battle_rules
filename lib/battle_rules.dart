/// Headless rules core of Battle Team: AP, movement, vision and combat.
///
/// Pure Dart with no I/O: the caller passes the YAML text of the game data
/// (`apps/battle_team/plan/data/` in the hawkbee checkout) and the time.
library;

export 'src/actions/action_result.dart';
export 'src/actions/capture.dart';
export 'src/actions/hq_move.dart';
export 'src/actions/push.dart';
export 'src/actions/role_actions.dart';
export 'src/ap/activity.dart';
export 'src/ap/ap_pool.dart';
export 'src/ap/movement.dart';
export 'src/combat/damage.dart';
export 'src/combat/first_person.dart';
export 'src/combat/hit_chance.dart';
export 'src/combat/morale.dart';
export 'src/combat/seeded_random.dart';
export 'src/combat/vec3.dart';
export 'src/combat/weapons.dart';
export 'src/combat/zero_hp.dart';
export 'src/data/battle_settings.dart' hide battleFile;
export 'src/data/combat_data.dart' hide combatFile;
export 'src/data/economy_data.dart';
export 'src/data/game_data.dart';
export 'src/data/game_data_exception.dart';
export 'src/data/hit_box.dart' show HitBox;
export 'src/data/medals_data.dart';
export 'src/data/terrain_data.dart' hide terrainFile;
export 'src/data/units_data.dart' hide unitsFile;
export 'src/movement/movement_cost.dart';
export 'src/scenario/scenario.dart' hide scenarioFile;
export 'src/scenario/scenario_runner.dart';
export 'src/vision/vision.dart';
