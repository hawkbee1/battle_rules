import 'dart:io';

/// Folder of the Battle Team game data in the hawkbee checkout, relative to
/// this package (stack decision 7). Tests run from the package folder.
///
/// The data is never copied into the package: tests on real values read it
/// from here, so the code and the data cannot drift apart silently.
const planDataPath = '../../apps/battle_team/plan/data';

/// Reads the text of the game data file [fileName] (for example
/// `units.yaml`) from [planDataPath].
///
/// Throws a [StateError] naming the missing path when the package is not
/// inside a hawkbee checkout.
String readPlanData(String fileName) {
  final file = File('$planDataPath/$fileName');
  if (!file.existsSync()) {
    throw StateError(
      '${file.absolute.path} not found. battle_rules tests read the game '
      'data from a hawkbee checkout: git clone --recurse-submodules '
      'https://github.com/hawkbee1/hawkbee.git',
    );
  }
  return file.readAsStringSync();
}
