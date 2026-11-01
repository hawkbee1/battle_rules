import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('readFixture', () {
    test('applies a replacement that occurs once', () {
      final text = readFixture('medals.yaml', {'kinds: [hit, build]': 'X'});

      expect(text, contains('\n  X\n'));
    });

    test('refuses a replacement that does not occur exactly once', () {
      expect(
        () => readFixture('medals.yaml', {'bronze': 'X'}),
        throwsA(isA<StateError>()),
      );
    });
  });
}
