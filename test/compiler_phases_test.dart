import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Compiler phase extraction smoke test', () {
    late Compiler compiler;
    setUp(() {
      compiler = Compiler();
    });

    test('Simple program', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {'main.dart': 'int main() => 42;'}
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 42);
    });

    test('Multi-file import', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart':
              "import 'helper.dart';\nint main() => double2(21);",
          'helper.dart': 'int double2(int x) => x + x;',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 42);
    });

    test('Class with methods', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            class Calc { int add(int a, int b) { return a + b; } }
            int main() { return Calc().add(19, 23); }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 42);
    });

    test('Generic collection', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              final list = <int>[1, 2, 3];
              int sum = 0;
              for (final item in list) { sum = sum + item; }
              return sum;
            }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 6);
    });

    test('Closure with captured variable', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              int x = 10;
              var fn = () { return x + 5; };
              return fn();
            }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 15);
    });

    test('Try-catch', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              try { throw 'err'; } catch (e) { return 99; }
            }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 99);
    });
  });
}
