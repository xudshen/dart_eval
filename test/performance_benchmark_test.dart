import 'package:dart_eval/dart_eval.dart';
import 'package:test/test.dart';

/// Performance benchmark tests for dart_eval
/// These tests measure execution time for common operations
void main() {
  group('Performance Benchmarks', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Benchmark 1: Deep function call stack (tests frame allocation)', () {
      final runtime = compiler.compileWriteAndLoad({
        'bench': {
          'main.dart': '''
            int recursiveSum(int n) {
              if (n <= 0) return 0;
              return n + recursiveSum(n - 1);
            }

            int main() {
              int result = 0;
              for (int i = 0; i < 100; i++) {
                result += recursiveSum(50);
              }
              return result;
            }
          '''
        }
      });

      final stopwatch = Stopwatch()..start();
      final result = runtime.executeLib('package:bench/main.dart', 'main');
      stopwatch.stop();

      expect(result, 127500); // 100 * (50 * 51 / 2)
      print('Benchmark 1 (Deep function calls): ${stopwatch.elapsedMilliseconds}ms');
    });

    test('Benchmark 2: Collection boxing operations', () {
      final runtime = compiler.compileWriteAndLoad({
        'bench': {
          'main.dart': '''
            int main() {
              int sum = 0;
              for (int i = 0; i < 100; i++) {
                List<int> list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
                Map<String, int> map = {'a': 1, 'b': 2, 'c': 3, 'd': 4, 'e': 5};
                Set<int> set = {1, 2, 3, 4, 5};
                sum += list.length + map.length + set.length;
              }
              return sum;
            }
          '''
        }
      });

      final stopwatch = Stopwatch()..start();
      final result = runtime.executeLib('package:bench/main.dart', 'main');
      stopwatch.stop();

      expect(result, 2000); // 100 * (10 + 5 + 5)
      print('Benchmark 2 (Collection boxing): ${stopwatch.elapsedMilliseconds}ms');
    });

    test('Benchmark 3: Method calls with inheritance chain', () {
      final runtime = compiler.compileWriteAndLoad({
        'bench': {
          'main.dart': '''
            class A {
              int getValue() => 1;
            }

            class B extends A {
              @override
              int getValue() => super.getValue() + 1;
            }

            class C extends B {
              @override
              int getValue() => super.getValue() + 1;
            }

            class D extends C {
              @override
              int getValue() => super.getValue() + 1;
            }

            int main() {
              D d = D();
              int sum = 0;
              for (int i = 0; i < 1000; i++) {
                sum += d.getValue();
              }
              return sum;
            }
          '''
        }
      });

      final stopwatch = Stopwatch()..start();
      final result = runtime.executeLib('package:bench/main.dart', 'main');
      stopwatch.stop();

      expect(result, 4000); // 1000 * 4
      print('Benchmark 3 (Inheritance method calls): ${stopwatch.elapsedMilliseconds}ms');
    });

    test('Benchmark 4: Property access patterns', () {
      final runtime = compiler.compileWriteAndLoad({
        'bench': {
          'main.dart': '''
            class Point {
              int x;
              int y;
              Point(this.x, this.y);

              int get sum => x + y;
            }

            int main() {
              Point p = Point(10, 20);
              int result = 0;
              for (int i = 0; i < 1000; i++) {
                result += p.x + p.y + p.sum;
              }
              return result;
            }
          '''
        }
      });

      final stopwatch = Stopwatch()..start();
      final result = runtime.executeLib('package:bench/main.dart', 'main');
      stopwatch.stop();

      expect(result, 60000); // 1000 * (10 + 20 + 30)
      print('Benchmark 4 (Property access): ${stopwatch.elapsedMilliseconds}ms');
    });

    test('Benchmark 5: Arithmetic operations (baseline)', () {
      final runtime = compiler.compileWriteAndLoad({
        'bench': {
          'main.dart': '''
            int main() {
              int sum = 0;
              for (int i = 0; i < 10000; i++) {
                sum += i * 2 - i + 1;
              }
              return sum;
            }
          '''
        }
      });

      final stopwatch = Stopwatch()..start();
      final result = runtime.executeLib('package:bench/main.dart', 'main');
      stopwatch.stop();

      // i * 2 - i + 1 = i + 1, so sum = sum(1 to 10000) = 10000 * 10001 / 2 = 50005000
      expect(result, 50005000);
      print('Benchmark 5 (Arithmetic baseline): ${stopwatch.elapsedMilliseconds}ms');
    });

    test('Benchmark 6: Large list operations', () {
      final runtime = compiler.compileWriteAndLoad({
        'bench': {
          'main.dart': '''
            int main() {
              List<int> list = [];
              for (int i = 0; i < 500; i++) {
                list.add(i);
              }
              int sum = 0;
              for (int i = 0; i < list.length; i++) {
                sum += list[i];
              }
              return sum;
            }
          '''
        }
      });

      final stopwatch = Stopwatch()..start();
      final result = runtime.executeLib('package:bench/main.dart', 'main');
      stopwatch.stop();

      expect(result, 124750); // 0 + 1 + ... + 499 = 499 * 500 / 2
      print('Benchmark 6 (Large list operations): ${stopwatch.elapsedMilliseconds}ms');
    });
  });
}
