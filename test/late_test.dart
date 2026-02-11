import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Late variables', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('late local variable with initializer', () {
      final runtime = compiler.compileWriteAndLoad({
        'late_test': {
          'main.dart': '''
            int main() {
              late int value = 21 * 2;
              return value;
            }
          '''
        }
      });
      expect(runtime.executeLib('package:late_test/main.dart', 'main'), 42);
    });

    test('late field assignment and read', () {
      final runtime = compiler.compileWriteAndLoad({
        'late_test': {
          'main.dart': '''
            class Config {
              late int count;

              void init(int n) {
                count = n;
              }
            }

            int main() {
              final config = Config();
              config.init(42);
              return config.count;
            }
          '''
        }
      });
      expect(runtime.executeLib('package:late_test/main.dart', 'main'), 42);
    });

    test('late final variable', () {
      final runtime = compiler.compileWriteAndLoad({
        'late_test': {
          'main.dart': '''
            int main() {
              late final int x = 10 + 20;
              return x;
            }
          '''
        }
      });
      expect(runtime.executeLib('package:late_test/main.dart', 'main'), 30);
    });

    test('late variable in function', () {
      final runtime = compiler.compileWriteAndLoad({
        'late_test': {
          'main.dart': '''
            int compute(int a, int b) {
              late int sum = a + b;
              late int product = a * b;
              return sum + product;
            }

            int main() {
              return compute(3, 4);
            }
          '''
        }
      });
      // sum = 7, product = 12, result = 19
      expect(runtime.executeLib('package:late_test/main.dart', 'main'), 19);
    });
  });
}
