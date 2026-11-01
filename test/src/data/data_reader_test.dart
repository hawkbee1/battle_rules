import 'package:battle_rules/src/data/data_reader.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

const _sample = '''
count: 3
ratio: 0.5
whole: 2
name: alpha
flag: true
nothing: null
box: { side: 1 }
groups:
  first: { side: 2 }
  second: { side: 3 }
names: [a, b]
bad_names: [a, 1]
counts: [1, 2]
bad_counts: [1, 2.5]
values: [1, 2.5]
bad_values: [1, x]
tally: { a: 1, b: 2 }
weights: { a: 1, b: 0.5 }
gaps: { a: 1, b: null }
numbered: { 1: a }
''';

DataReader _reader() => DataReader.parse('sample.yaml', _sample);

void main() {
  group(DataReader, () {
    group('parse', () {
      test('reads a map document', () {
        final reader = _reader();

        expect(reader.file, 'sample.yaml');
        expect(reader.path, isEmpty);
        expect(reader.keys, contains('count'));
      });

      test('rejects invalid YAML', () {
        expect(
          () => DataReader.parse('sample.yaml', 'a: [1, 2'),
          throwsDataError('sample.yaml', '', null, 'invalid YAML'),
        );
      });

      test('rejects a document that is not a map', () {
        expect(
          () => DataReader.parse('sample.yaml', '- a\n- b'),
          throwsDataError('sample.yaml', '', ['a', 'b'], 'must be a map'),
        );
      });

      test('rejects an empty document', () {
        expect(
          () => DataReader.parse('sample.yaml', ''),
          throwsDataError('sample.yaml', '', null, 'must be a map'),
        );
      });
    });

    test('has tells present keys, null values included', () {
      final reader = _reader();

      expect(reader.has('nothing'), isTrue);
      expect(reader.has('absent'), isFalse);
    });

    test('keys rejects a key that is not a string', () {
      expect(
        () => _reader().map('numbered').keys.toList(),
        throwsDataError(
          'sample.yaml',
          'numbered.1',
          1,
          'a key must be a string',
        ),
      );
    });

    test('keyPath joins nested keys with dots', () {
      final reader = _reader();

      expect(reader.keyPath('box'), 'box');
      expect(reader.map('box').keyPath('side'), 'box.side');
    });

    test('fail names the file, the key path and the value', () {
      expect(
        () => _reader().map('box').fail('side', 1, 'too small'),
        throwsDataError('sample.yaml', 'box.side', 1, 'too small'),
      );
    });

    group('map', () {
      test('reads a nested map', () {
        expect(_reader().map('box').integer('side'), 1);
      });

      test('rejects a missing key', () {
        expect(
          () => _reader().map('absent'),
          throwsDataError('sample.yaml', 'absent', null, 'missing'),
        );
      });

      test('rejects a value that is not a map', () {
        expect(
          () => _reader().map('count'),
          throwsDataError('sample.yaml', 'count', 3, 'must be a map'),
        );
      });

      test('optionalMap reads null for an absent or null value', () {
        final reader = _reader();

        expect(reader.optionalMap('absent'), isNull);
        expect(reader.optionalMap('nothing'), isNull);
        expect(reader.optionalMap('box')?.integer('side'), 1);
        expect(
          () => reader.optionalMap('count'),
          throwsDataError('sample.yaml', 'count', 3, 'must be a map'),
        );
      });

      test('maps reads every value as a map', () {
        final groups = _reader().map('groups').maps();

        expect(groups.keys, ['first', 'second']);
        expect(groups['second']?.integer('side'), 3);
        expect(groups['second']?.path, 'groups.second');
      });
    });

    group('scalars', () {
      test('integer reads an integer and rejects anything else', () {
        final reader = _reader();

        expect(reader.integer('count'), 3);
        expect(
          () => reader.integer('ratio'),
          throwsDataError('sample.yaml', 'ratio', 0.5, 'must be an integer'),
        );
      });

      test('number reads an integer or a double as a double', () {
        final reader = _reader();

        expect(reader.number('whole'), 2.0);
        expect(reader.number('ratio'), 0.5);
        expect(
          () => reader.number('name'),
          throwsDataError('sample.yaml', 'name', 'alpha', 'must be a number'),
        );
      });

      test('optionalNumber reads null for an absent or null value', () {
        final reader = _reader();

        expect(reader.optionalNumber('absent'), isNull);
        expect(reader.optionalNumber('nothing'), isNull);
        expect(reader.optionalNumber('ratio'), 0.5);
        expect(
          () => reader.optionalNumber('name'),
          throwsDataError('sample.yaml', 'name', 'alpha', 'must be a number'),
        );
      });

      test('numberOrNull needs the key but accepts null', () {
        final reader = _reader();

        expect(reader.numberOrNull('nothing'), isNull);
        expect(reader.numberOrNull('ratio'), 0.5);
        expect(
          () => reader.numberOrNull('absent'),
          throwsDataError('sample.yaml', 'absent', null, 'missing'),
        );
      });

      test('string reads a string and rejects anything else', () {
        final reader = _reader();

        expect(reader.string('name'), 'alpha');
        expect(
          () => reader.string('count'),
          throwsDataError('sample.yaml', 'count', 3, 'must be a string'),
        );
      });

      test('optionalString reads null for an absent or null value', () {
        final reader = _reader();

        expect(reader.optionalString('absent'), isNull);
        expect(reader.optionalString('nothing'), isNull);
        expect(reader.optionalString('name'), 'alpha');
        expect(
          () => reader.optionalString('count'),
          throwsDataError('sample.yaml', 'count', 3, 'must be a string'),
        );
      });

      test('stringOrNull needs the key but accepts null', () {
        final reader = _reader();

        expect(reader.stringOrNull('nothing'), isNull);
        expect(reader.stringOrNull('name'), 'alpha');
        expect(
          () => reader.stringOrNull('absent'),
          throwsDataError('sample.yaml', 'absent', null, 'missing'),
        );
      });

      test('boolean reads true or false and rejects anything else', () {
        final reader = _reader();

        expect(reader.boolean('flag'), isTrue);
        expect(
          () => reader.boolean('name'),
          throwsDataError('sample.yaml', 'name', 'alpha', 'true or false'),
        );
      });

      test('optionalBoolean reads the given default when absent or null', () {
        final reader = _reader();

        expect(reader.optionalBoolean('absent', absent: true), isTrue);
        expect(reader.optionalBoolean('nothing', absent: false), isFalse);
        expect(reader.optionalBoolean('flag', absent: false), isTrue);
        expect(
          () => reader.optionalBoolean('name', absent: true),
          throwsDataError('sample.yaml', 'name', 'alpha', 'true or false'),
        );
      });
    });

    group('lists', () {
      test('strings reads a list of strings', () {
        expect(_reader().strings('names'), ['a', 'b']);
      });

      test('strings rejects a value that is not a list', () {
        expect(
          () => _reader().strings('name'),
          throwsDataError('sample.yaml', 'name', 'alpha', 'must be a list'),
        );
      });

      test('strings rejects an item that is not a string', () {
        expect(
          () => _reader().strings('bad_names'),
          throwsDataError('sample.yaml', 'bad_names[1]', 1, 'a string'),
        );
      });

      test('optionalStrings reads an empty list when absent', () {
        final reader = _reader();

        expect(reader.optionalStrings('absent'), isEmpty);
        expect(reader.optionalStrings('names'), ['a', 'b']);
      });

      test('integers reads integers and rejects other items', () {
        final reader = _reader();

        expect(reader.integers('counts'), [1, 2]);
        expect(
          () => reader.integers('bad_counts'),
          throwsDataError('sample.yaml', 'bad_counts[1]', 2.5, 'an integer'),
        );
      });

      test('numbers reads numbers as doubles and rejects other items', () {
        final reader = _reader();

        expect(reader.numbers('values'), [1.0, 2.5]);
        expect(
          () => reader.numbers('bad_values'),
          throwsDataError('sample.yaml', 'bad_values[1]', 'x', 'a number'),
        );
      });

      test('lists are unmodifiable', () {
        final reader = _reader();

        expect(() => reader.strings('names').add('c'), throwsUnsupportedError);
        expect(() => reader.integers('counts').add(3), throwsUnsupportedError);
        expect(() => reader.numbers('values').add(3), throwsUnsupportedError);
      });
    });

    group('entries', () {
      test('integerEntries reads every value as an integer', () {
        expect(_reader().map('tally').integerEntries(), {'a': 1, 'b': 2});
      });

      test('numberEntries reads every value as a number', () {
        expect(_reader().map('weights').numberEntries(), {'a': 1.0, 'b': 0.5});
      });

      test('entries are unmodifiable', () {
        final reader = _reader();

        expect(
          () => reader.map('tally').integerEntries()['c'] = 3,
          throwsUnsupportedError,
        );
        expect(
          () => reader.map('weights').numberEntries()['c'] = 3,
          throwsUnsupportedError,
        );
        expect(
          () => reader.map('gaps').numberOrNullEntries()['c'] = 3,
          throwsUnsupportedError,
        );
      });

      test('numberOrNullEntries keeps null values', () {
        expect(_reader().map('gaps').numberOrNullEntries(), {
          'a': 1.0,
          'b': null,
        });
      });
    });
  });
}
