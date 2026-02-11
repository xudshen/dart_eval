import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Mixin support', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('basic mixin declaration and usage', () {
      final runtime = compiler.compileWriteAndLoad({
        'mixin_test': {
          'main.dart': '''
            mixin Greetable {
              int greetCode() => 42;
            }

            class Person with Greetable {
              final int id;
              Person(this.id);
            }

            int main() {
              final p = Person(1);
              return p.greetCode();
            }
          '''
        }
      });
      expect(
          runtime.executeLib('package:mixin_test/main.dart', 'main'), 42);
    });

    test('mixin with method override', () {
      final runtime = compiler.compileWriteAndLoad({
        'mixin_test': {
          'main.dart': '''
            mixin Describable {
              int describe() => 0;
            }

            class Animal with Describable {
              final int code;
              Animal(this.code);

              @override
              int describe() => code;
            }

            int main() {
              return Animal(99).describe();
            }
          '''
        }
      });
      expect(
          runtime.executeLib('package:mixin_test/main.dart', 'main'), 99);
    });

    test('multiple mixins', () {
      final runtime = compiler.compileWriteAndLoad({
        'mixin_test': {
          'main.dart': '''
            mixin A {
              int getA() => 1;
            }

            mixin B {
              int getB() => 2;
            }

            class C with A, B {}

            int main() {
              final c = C();
              return c.getA() + c.getB();
            }
          '''
        }
      });
      expect(
          runtime.executeLib('package:mixin_test/main.dart', 'main'), 3);
    });
  });
}
