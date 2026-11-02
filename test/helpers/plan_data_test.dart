import 'package:test/test.dart';

import 'plan_data.dart';

void main() {
  group('readPlanData', () {
    test('finds units.yaml in the hawkbee checkout', () {
      final text = readPlanData('units.yaml');

      expect(text, contains(RegExp('^units:', multiLine: true)));
    });

    test('names the missing path when a file is not found', () {
      expect(
        () => readPlanData('missing.yaml'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('missing.yaml'), contains('hawkbee checkout')),
          ),
        ),
      );
    });
  });

  group('readPlanEconomy', () {
    test('finds economy.yaml in plan/milestones', () {
      final text = readPlanEconomy();

      expect(text, contains(RegExp('^transfer_fees:', multiLine: true)));
    });
  });
}
