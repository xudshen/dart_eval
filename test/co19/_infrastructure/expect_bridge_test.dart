import 'package:dart_eval/dart_eval.dart';
import 'package:test/test.dart';

import 'expect_plugin.dart';

/// Helper: compile and run a co19 Expect test snippet.
/// The [source] is the body of a `void main() { ... }` function that
/// can use `import 'package:co19_expect/expect.dart';`.
Runtime _compile(String source) {
  final plugin = Co19ExpectPlugin();
  final compiler = Compiler();
  compiler.addPlugin(plugin);
  final runtime = compiler.compileWriteAndLoad({
    'eval_test': {
      'main.dart': '''
        import 'package:co19_expect/expect.dart';
        void main() {
          $source
        }
      '''
    }
  });
  plugin.configureForRuntime(runtime);
  return runtime;
}

void _run(Runtime runtime) {
  runtime.executeLib('package:eval_test/main.dart', 'main');
}

void main() {
  group('Co19ExpectPlugin', () {
    group('Expect.equals', () {
      test('passes when values are equal', () {
        final rt = _compile('''
          Expect.equals(1, 1);
          Expect.equals("hello", "hello");
          Expect.equals(true, true);
          Expect.equals(null, null);
        ''');
        // Should not throw
        _run(rt);
      });

      test('fails when values are not equal', () {
        final rt = _compile('''
          Expect.equals(1, 2);
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      });
    });

    group('Expect.notEquals', () {
      test('passes when values differ', () {
        final rt = _compile('''
          Expect.notEquals(1, 2);
          Expect.notEquals("a", "b");
        ''');
        _run(rt);
      });

      test('fails when values are equal', () {
        final rt = _compile('''
          Expect.notEquals(1, 1);
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      });
    });

    group('Expect.isTrue', () {
      test('passes for true', () {
        final rt = _compile('''
          Expect.isTrue(true);
        ''');
        _run(rt);
      });

      test('fails for false', () {
        final rt = _compile('''
          Expect.isTrue(false);
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      });

      test('fails for non-bool', () {
        final rt = _compile('''
          Expect.isTrue(1);
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      });
    });

    group('Expect.isFalse', () {
      test('passes for false', () {
        final rt = _compile('''
          Expect.isFalse(false);
        ''');
        _run(rt);
      });

      test('fails for true', () {
        final rt = _compile('''
          Expect.isFalse(true);
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      });
    });

    group('Expect.isNull', () {
      test('passes for null', () {
        final rt = _compile('''
          Expect.isNull(null);
        ''');
        _run(rt);
      });

      test('fails for non-null', () {
        final rt = _compile('''
          Expect.isNull(42);
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      });
    });

    group('Expect.isNotNull', () {
      test('passes for non-null', () {
        final rt = _compile('''
          Expect.isNotNull(42);
          Expect.isNotNull("hello");
        ''');
        _run(rt);
      });

      test('fails for null', () {
        final rt = _compile('''
          Expect.isNotNull(null);
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      });
    });

    group('Expect.throws', () {
      test('passes when function throws', () {
        final rt = _compile('''
          Expect.throws(() { throw Exception("boom"); });
        ''');
        _run(rt);
      }, tags: ['co19-lambda']);

      test('fails when function does not throw', () {
        final rt = _compile('''
          Expect.throws(() { });
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      }, tags: ['co19-lambda']);
    });

    group('Expect.listEquals', () {
      test('passes for equal lists', () {
        final rt = _compile('''
          Expect.listEquals([1, 2, 3], [1, 2, 3]);
        ''');
        _run(rt);
      });

      test('fails for different lists', () {
        final rt = _compile('''
          Expect.listEquals([1, 2], [1, 3]);
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      });
    });

    group('Expect.fail', () {
      test('always throws', () {
        final rt = _compile('''
          Expect.fail("intentional failure");
        ''');
        expect(() => _run(rt), throwsA(isA<Exception>()));
      });
    });
  });
}
