import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('readFixture', () {
    test('applies a replacement that occurs once', () {
      final text = readFixture('medals.yaml', {'kinds: [hit, build]': 'X'});

      expect(text, contains('\n  X\n'));
    });

    test('refuses a replacement that occurs more than once', () {
      expect(
        () => readFixture('medals.yaml', {'bronze': 'X'}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('"bronze" occurs 6 times'),
          ),
        ),
      );
    });

    test('refuses a replacement that does not occur', () {
      expect(
        () => readFixture('medals.yaml', {'platinum': 'X'}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('"platinum" occurs 0 times'),
          ),
        ),
      );
    });
  });
}
