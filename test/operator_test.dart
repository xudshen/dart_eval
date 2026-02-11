import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Operator method tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Operator ==', () {
      final runtime = compiler.compileWriteAndLoad({
        'operator_test': {
          'main.dart': '''
            class MyClass {
              final int value;
              
              MyClass(this.value);
              
              @override
              bool operator==(Object other) => other is MyClass && other.value == value;
            }
            
            List<bool> main() {
              final cls = MyClass(1);
              return [
                cls == MyClass(2),
                cls == null,
                cls == MyClass(1),
                cls == cls,
              ];
            }
          '''
        }
      });

      expect(runtime.executeLib('package:operator_test/main.dart', 'main'), [
        $bool(false), $bool(false), $bool(true), $bool(true),
      ]);
    });

    test('Operator has object context', () {
      final runtime = compiler.compileWriteAndLoad({
        'operator_test': {
          'main.dart': '''
            class MyClass {
              final int value = 1;
              int operator+(int add) => value + add;
            }
            int main() => MyClass() + 1;
          '''
        }
      });

      expect(runtime.executeLib('package:operator_test/main.dart', 'main'), 2);
    });

    test('Operator []', () {
      final runtime = compiler.compileWriteAndLoad({
        'operator_test': {
          'main.dart': '''
            class MyClass {
              final value = [1, 2];
              
              MyClass();
              
              int operator[](int index) => value[index];
              
              void operator[]=(int index, int value) {
                this.value[index] = value;
              }
            }
            
            List<int> main() {
              final cls = MyClass();
              cls[0] = 3;
              return [cls[0], cls[1]];
            }
          '''
        }
      });

      expect(runtime.executeLib('package:operator_test/main.dart', 'main'), [
        $int(1), $int(2),
      ]);
    }, skip: 'Requires fix for list field type inference (specifiedTypeArgs)');

    test('Operator - (subtraction)', () {
      final runtime = compiler.compileWriteAndLoad({
        'operator_test': {
          'main.dart': '''
            class Vec2 {
              final int x;
              final int y;
              Vec2(this.x, this.y);
              Vec2 operator+(Vec2 other) => Vec2(x + other.x, y + other.y);
              Vec2 operator-(Vec2 other) => Vec2(x - other.x, y - other.y);
            }
            List<int> main() {
              final a = Vec2(3, 4);
              final b = Vec2(1, 2);
              final sum = a + b;
              final diff = a - b;
              return [sum.x, sum.y, diff.x, diff.y];
            }
          '''
        }
      });
      expect(runtime.executeLib('package:operator_test/main.dart', 'main'),
          [$int(4), $int(6), $int(2), $int(2)]);
    });

    test('Operator < and >', () {
      final runtime = compiler.compileWriteAndLoad({
        'operator_test': {
          'main.dart': '''
            class Temp {
              final int value;
              Temp(this.value);
              bool operator<(Temp other) => value < other.value;
              bool operator>(Temp other) => value > other.value;
            }
            List<bool> main() {
              return [Temp(36) < Temp(37), Temp(38) > Temp(37)];
            }
          '''
        }
      });
      expect(runtime.executeLib('package:operator_test/main.dart', 'main'),
          [$bool(true), $bool(true)]);
    });
  });
}