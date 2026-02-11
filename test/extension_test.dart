import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Extension methods', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('extension method on custom class', () {
      final runtime = compiler.compileWriteAndLoad({
        'ext_test': {
          'main.dart': '''
            class Vec {
              final int x;
              final int y;
              Vec(this.x, this.y);
            }

            extension VecExt on Vec {
              int sum() => x + y;
            }

            int main() {
              return Vec(3, 4).sum();
            }
          '''
        }
      });
      expect(
          runtime.executeLib('package:ext_test/main.dart', 'main'), 7);
    });

    test('extension on int', skip: 'bridge type extensions not yet supported', () {
      final runtime = compiler.compileWriteAndLoad({
        'ext_test': {
          'main.dart': '''
            extension IntSquare on int {
              int square() => this * this;
            }

            int main() => 5.square();
          '''
        }
      });
      expect(
          runtime.executeLib('package:ext_test/main.dart', 'main'), 25);
    });
  });
}
