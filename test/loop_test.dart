import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Loop tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('For loop', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              for (; i < 555; i++) {}
              return i;
            }
          ''',
        }
      });
      expect(
          runtime.executeLib('package:example/main.dart', 'main'), $int(555));
    });

    test('For loop + branching', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
          dynamic doThing() {
            var count = 0;
            for (var i = 0; i < 1000; i++) {
              if (count < 500) {
                count--;
              } else if (count < 750) {
                count++;
              }
              count += i;
            }
            
            return count;
          }
        '''
        }
      });

      expect(runtime.executeLib('package:example/main.dart', 'doThing'),
          $int(499472));
    });

    test('Simple foreach', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              for (var x in [1, 2, 3, 4, 5]) {
                i += x;
              }
              return i;
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), $int(15));
    });

    test('Foreach with dynamic iterable, specifying type in loop', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              dynamic list = [[1, 2], [3, 4], [5]];
              for (List<int> x in list) {
                i += x[0];
              }
              i++;
              return i;
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), $int(10));
    });

    test('Simple while loop', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              while (i < 555) {
                i++;
              }
              return i;
            }
          ''',
        }
      });
      expect(
          runtime.executeLib('package:example/main.dart', 'main'), $int(555));
    });

    test('Simple do-while loop', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              do {
                i++;
              } while (i < 555);
              return i;
            }
          ''',
        }
      });
      expect(
          runtime.executeLib('package:example/main.dart', 'main'), $int(555));
    });

    test('For loop with break', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              for (; i < 555; i++) {
                print(i);
                if (i == 5) {
                  break;
                }
              }
              return i;
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), $int(5));
    });

    test('Nested for loop with break', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              var j = 0;
              for (; i < 555; i++) {
                for (; j < 555; j++) {
                  if (j == 100) {
                    break;
                  }
                }
                if (i == 100) {
                  break;
                }
              }
              return i * 1000 + j;
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(100100));
    });
  });

  group('For loop closure capture', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Basic: each iteration captures its own i value', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            dynamic main() {
              var fn0 = () { return -1; };
              var fn1 = () { return -1; };
              var fn2 = () { return -1; };
              for (int i = 0; i < 3; i++) {
                if (i == 0) {
                  fn0 = () { return i; };
                }
                if (i == 1) {
                  fn1 = () { return i; };
                }
                if (i == 2) {
                  fn2 = () { return i; };
                }
              }
              return fn0() * 100 + fn1() * 10 + fn2();
            }
          ''',
        }
      });
      // Each closure captures its iteration's i: fn0()=0, fn1()=1, fn2()=2
      // 0*100 + 1*10 + 2 = 12
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(12));
    });

    test('For-each: each iteration captures its own element', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            dynamic main() {
              var fn0 = () { return -1; };
              var fn1 = () { return -1; };
              var fn2 = () { return -1; };
              var idx = 0;
              for (var x in [10, 20, 30]) {
                if (idx == 0) {
                  fn0 = () { return x; };
                }
                if (idx == 1) {
                  fn1 = () { return x; };
                }
                if (idx == 2) {
                  fn2 = () { return x; };
                }
                idx = idx + 1;
              }
              return fn0() + fn1() + fn2();
            }
          ''',
        }
      });
      // fn0()=10, fn1()=20, fn2()=30 → 60
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(60));
    });

    test('Parent scope access: closure reads both loop var and outer var', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            dynamic main() {
              var x = 100;
              var fn0 = () { return -1; };
              var fn1 = () { return -1; };
              for (int i = 0; i < 2; i++) {
                if (i == 0) {
                  fn0 = () { return x + i; };
                }
                if (i == 1) {
                  fn1 = () { return x + i; };
                }
              }
              return fn0() + fn1();
            }
          ''',
        }
      });
      // fn0()=100+0=100, fn1()=100+1=101 → 201
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(201));
    });

    test('Diagnostic: closure reassignment inside loop, no capture', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            dynamic main() {
              var fn = () { return 1; };
              for (int i = 0; i < 3; i++) {
                fn = () { return 99; };
              }
              return fn();
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(99));
    });

    test('Diagnostic: closure reassignment inside loop, captures i', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            dynamic main() {
              var fn = () { return -1; };
              for (int i = 0; i < 3; i++) {
                fn = () { return i; };
              }
              return fn();
            }
          ''',
        }
      });
      // With per-iteration scope, fn captures iteration 2's i = 2
      // (Dart semantics: each for-loop iteration has its own variable binding)
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(2));
    });

    test('Break inside loop with closure capture preserves captured value', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            dynamic main() {
              var fn = () { return -1; };
              for (int i = 0; i < 10; i++) {
                if (i == 2) {
                  fn = () { return i; };
                  break;
                }
              }
              return fn();
            }
          ''',
        }
      });
      // fn captures i = 2 from the iteration that executed break
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(2));
    });

    test('Break with unmodified closure var preserves function value', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            dynamic main() {
              var fn = () { return 42; };
              for (int i = 0; i < 10; i++) {
                if (i == 2) { break; }
              }
              return fn();
            }
          ''',
        }
      });
      // fn should retain its original value after break
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(42));
    });

    test('No closure: for loop without closures still works normally', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            dynamic main() {
              var sum = 0;
              for (int i = 0; i < 5; i++) {
                sum = sum + i;
              }
              return sum;
            }
          ''',
        }
      });
      // 0+1+2+3+4 = 10
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(10));
    });
  });

  group('For loop variable as method argument (RT-006)', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Loop variable passed to method inside loop body', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String helper(int idx) {
              return 'item_' + idx.toString();
            }

            String main() {
              var result = '';
              for (int i = 0; i < 3; i++) {
                result = result + helper(i) + ',';
              }
              return result;
            }
          ''',
        }
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('item_0,item_1,item_2,'),
      );
    });

    test('Loop variable and list indexing passed to method', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String makeLabel(int idx, String text) {
              return idx.toString() + ':' + text;
            }

            String main() {
              var items = ['apple', 'banana', 'cherry'];
              var result = '';
              for (int i = 0; i < 3; i++) {
                result = result + makeLabel(i, items[i]) + ',';
              }
              return result;
            }
          ''',
        }
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('0:apple,1:banana,2:cherry,'),
      );
    });

    test('For-each variable passed to method', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String wrap(String s) {
              return '[' + s + ']';
            }

            String main() {
              var result = '';
              for (var item in ['a', 'b', 'c']) {
                result = result + wrap(item);
              }
              return result;
            }
          ''',
        }
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('[a][b][c]'),
      );
    });

    test('No-closure: sum of method results using loop variable', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int transform(int x) { return x * 10; }
            int main() {
              var sum = 0;
              for (int i = 0; i < 3; i++) {
                var t = transform(i);
                sum = sum + t;
              }
              return sum;
            }
          '''
        }
      });
      // 0+10+20 = 30
      expect(runtime.executeLib('package:example/main.dart', 'main'), 30);
    });

    test('Capture body-local from inline expression', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            dynamic main() {
              var fn0 = () { return -1; };
              var fn1 = () { return -1; };
              var fn2 = () { return -1; };
              for (int i = 0; i < 3; i++) {
                var t = i * 10;
                if (i == 0) fn0 = () { return t; };
                if (i == 1) fn1 = () { return t; };
                if (i == 2) fn2 = () { return t; };
              }
              return fn0() * 10000 + fn1() * 100 + fn2();
            }
          '''
        }
      });
      // fn0=0, fn1=10, fn2=20 → 0*10000 + 10*100 + 20 = 1020
      expect(runtime.executeLib('package:example/main.dart', 'main'),
          $int(1020));
    });

    test('Capture body-local from method call (combined RT-002+RT-006)', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int transform(int x) { return x * 10; }

            dynamic main() {
              var fn0 = () { return -1; };
              var fn1 = () { return -1; };
              var fn2 = () { return -1; };
              for (int i = 0; i < 3; i++) {
                var t = transform(i);
                if (i == 0) fn0 = () { return t; };
                if (i == 1) fn1 = () { return t; };
                if (i == 2) fn2 = () { return t; };
              }
              return fn0() + fn1() + fn2();
            }
          ''',
        }
      });
      // transform(0)=0, transform(1)=10, transform(2)=20 -> 30
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $int(30),
      );
    });
  });
}
