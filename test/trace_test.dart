import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Execution tracing', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Simple program executes correctly with trace disabled', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              int a = 3;
              int b = 4;
              return a + b;
            }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 7);
    });

    test('Closure execution with trace disabled', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              var fn = (int x) { return x * 2; };
              return fn(21);
            }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 42);
    });

    test('Async execution with trace disabled', () async {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            import 'dart:async';
            Future<int> main() async {
              await Future.delayed(Duration(milliseconds: 1));
              return 99;
            }
          '''
        }
      });
      final result = runtime.executeLib('package:example/main.dart', 'main');
      await expectLater(result as Future, completion($int(99)));
    });
  });
}
