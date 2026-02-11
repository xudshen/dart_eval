import 'package:dart_eval/dart_eval.dart';
import 'package:test/test.dart';

void main() {
  group('Stack synchronization', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Simple function call maintains stack sync', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int add(int a, int b) {
              return a + b;
            }
            int main() {
              return add(3, 4);
            }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 7);
    });

    test('Nested function calls maintain stack sync', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int twice(int x) { return x + x; }
            int quadruple(int x) { return twice(twice(x)); }
            int main() {
              return quadruple(3);
            }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 12);
    });

    test('Closure with captured variable maintains stack sync', () {
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

    test('Try-catch maintains stack sync', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              try {
                throw 'error';
              } catch (e) {
                return 42;
              }
            }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 42);
    });

    test('For loop maintains stack sync', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              int sum = 0;
              for (int i = 0; i < 5; i = i + 1) {
                sum = sum + i;
              }
              return sum;
            }
          '''
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 10);
    });
  });
}
