import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Switch expressions', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('basic switch expression', () {
      final runtime = compiler.compileWriteAndLoad({
        'switch_expr_test': {
          'main.dart': '''
            String describe(int n) {
              return switch (n) {
                0 => 'zero',
                1 => 'one',
                _ => 'other',
              };
            }

            String main() => describe(1);
          '''
        }
      });
      final result =
          runtime.executeLib('package:switch_expr_test/main.dart', 'main');
      expect((result as $String).$value, 'one');
    });

    test('switch expression with int result', () {
      final runtime = compiler.compileWriteAndLoad({
        'switch_expr_test': {
          'main.dart': '''
            int main() {
              final x = 'hello';
              final len = switch (x) {
                'hi' => 2,
                'hello' => 5,
                _ => 0,
              };
              return len;
            }
          '''
        }
      });
      expect(runtime.executeLib('package:switch_expr_test/main.dart', 'main'),
          5);
    });

    test('switch expression with wildcard default', () {
      final runtime = compiler.compileWriteAndLoad({
        'switch_expr_test': {
          'main.dart': '''
            String main() {
              final val = 99;
              return switch (val) {
                1 => 'one',
                2 => 'two',
                _ => 'many',
              };
            }
          '''
        }
      });
      final result =
          runtime.executeLib('package:switch_expr_test/main.dart', 'main');
      expect((result as $String).$value, 'many');
    });
  });
}
