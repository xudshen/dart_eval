/// Performance Comparison Benchmark
/// Compares dart_eval (optimized) vs native Dart performance
///
/// Run with: dart run benchmark/performance_comparison.dart

import 'package:dart_eval/dart_eval.dart';

void main() {
  print('=' * 70);
  print('dart_eval Performance Comparison Benchmark');
  print('=' * 70);
  print('');

  final results = <String, Map<String, double>>{};

  // Benchmark 1: Recursive function calls
  results['1. Recursive calls'] = benchmark1();

  // Benchmark 2: Loop with arithmetic
  results['2. Loop arithmetic'] = benchmark2();

  // Benchmark 3: Object method calls
  results['3. Object methods'] = benchmark3();

  // Benchmark 4: Property access
  results['4. Property access'] = benchmark4();

  // Benchmark 5: List operations
  results['5. List operations'] = benchmark5();

  // Benchmark 6: Collection iteration
  results['6. Collection iter'] = benchmark6();

  // Print summary
  print('');
  print('=' * 70);
  print('SUMMARY');
  print('=' * 70);
  print('');
  print('| Benchmark           | dart_eval  | Native Dart | Slowdown   |');
  print('|---------------------|------------|-------------|------------|');

  for (final entry in results.entries) {
    final evalTime = entry.value['dart_eval']!;
    final nativeTime = entry.value['native']!;
    final ratio = nativeTime > 0 ? (evalTime / nativeTime) : double.infinity;
    final ratioStr = ratio.isFinite ? '${ratio.toStringAsFixed(0)}x' : 'N/A';
    print('| ${entry.key.padRight(19)} | ${evalTime.toStringAsFixed(2).padLeft(8)}ms | ${nativeTime.toStringAsFixed(2).padLeft(9)}ms | ${ratioStr.padLeft(10)} |');
  }

  print('');
  print('Note: Slowdown = dart_eval time / native time');
  print('      dart_eval is an interpreter, so ~50-500x slower than native is expected');
}

Map<String, double> benchmark1() {
  print('Benchmark 1: Recursive calls (sum 1..50, 1000 iterations)');
  print('-' * 60);

  // dart_eval version
  final compiler = Compiler();
  final runtime = compiler.compileWriteAndLoad({
    'bench': {
      'main.dart': '''
        int recursiveSum(int n) {
          if (n <= 0) return 0;
          return n + recursiveSum(n - 1);
        }

        int main() {
          int result = 0;
          for (int i = 0; i < 1000; i++) {
            result += recursiveSum(50);
          }
          return result;
        }
      '''
    }
  });

  final evalWatch = Stopwatch()..start();
  final evalResult = runtime.executeLib('package:bench/main.dart', 'main');
  evalWatch.stop();
  final evalMs = evalWatch.elapsedMicroseconds / 1000.0;
  print('  dart_eval: ${evalMs.toStringAsFixed(2)}ms (result: $evalResult)');

  // Native Dart version - run multiple times for accuracy
  int recursiveSum(int n) {
    if (n <= 0) return 0;
    return n + recursiveSum(n - 1);
  }

  final nativeWatch = Stopwatch()..start();
  int nativeResult = 0;
  for (int i = 0; i < 1000; i++) {
    nativeResult += recursiveSum(50);
  }
  nativeWatch.stop();
  final nativeMs = nativeWatch.elapsedMicroseconds / 1000.0;
  print('  Native:    ${nativeMs.toStringAsFixed(2)}ms (result: $nativeResult)');
  print('');

  return {'dart_eval': evalMs, 'native': nativeMs};
}

Map<String, double> benchmark2() {
  print('Benchmark 2: Loop with arithmetic (100000 iterations)');
  print('-' * 60);

  final compiler = Compiler();
  final runtime = compiler.compileWriteAndLoad({
    'bench': {
      'main.dart': '''
        int main() {
          int sum = 0;
          for (int i = 0; i < 100000; i++) {
            sum += i * 2 - i + 1;
          }
          return sum;
        }
      '''
    }
  });

  final evalWatch = Stopwatch()..start();
  final evalResult = runtime.executeLib('package:bench/main.dart', 'main');
  evalWatch.stop();
  final evalMs = evalWatch.elapsedMicroseconds / 1000.0;
  print('  dart_eval: ${evalMs.toStringAsFixed(2)}ms (result: $evalResult)');

  // Native Dart version
  final nativeWatch = Stopwatch()..start();
  int sum = 0;
  for (int i = 0; i < 100000; i++) {
    sum += i * 2 - i + 1;
  }
  nativeWatch.stop();
  final nativeMs = nativeWatch.elapsedMicroseconds / 1000.0;
  print('  Native:    ${nativeMs.toStringAsFixed(2)}ms (result: $sum)');
  print('');

  return {'dart_eval': evalMs, 'native': nativeMs};
}

Map<String, double> benchmark3() {
  print('Benchmark 3: Object method calls (10000 iterations)');
  print('-' * 60);

  final compiler = Compiler();
  final runtime = compiler.compileWriteAndLoad({
    'bench': {
      'main.dart': '''
        class Counter {
          int value = 0;
          int increment() {
            value = value + 1;
            return value;
          }
        }

        int main() {
          Counter c = Counter();
          int sum = 0;
          for (int i = 0; i < 10000; i++) {
            sum += c.increment();
          }
          return sum;
        }
      '''
    }
  });

  final evalWatch = Stopwatch()..start();
  final evalResult = runtime.executeLib('package:bench/main.dart', 'main');
  evalWatch.stop();
  final evalMs = evalWatch.elapsedMicroseconds / 1000.0;
  print('  dart_eval: ${evalMs.toStringAsFixed(2)}ms (result: $evalResult)');

  // Native Dart version
  final nativeWatch = Stopwatch()..start();
  final c = _Counter();
  int nativeSum = 0;
  for (int i = 0; i < 10000; i++) {
    nativeSum += c.increment();
  }
  nativeWatch.stop();
  final nativeMs = nativeWatch.elapsedMicroseconds / 1000.0;
  print('  Native:    ${nativeMs.toStringAsFixed(2)}ms (result: $nativeSum)');
  print('');

  return {'dart_eval': evalMs, 'native': nativeMs};
}

class _Counter {
  int value = 0;
  int increment() {
    value = value + 1;
    return value;
  }
}

Map<String, double> benchmark4() {
  print('Benchmark 4: Property access (10000 iterations)');
  print('-' * 60);

  final compiler = Compiler();
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
          for (int i = 0; i < 10000; i++) {
            result += p.x + p.y + p.sum;
          }
          return result;
        }
      '''
    }
  });

  final evalWatch = Stopwatch()..start();
  final evalResult = runtime.executeLib('package:bench/main.dart', 'main');
  evalWatch.stop();
  final evalMs = evalWatch.elapsedMicroseconds / 1000.0;
  print('  dart_eval: ${evalMs.toStringAsFixed(2)}ms (result: $evalResult)');

  // Native Dart version
  final nativeWatch = Stopwatch()..start();
  final p = _Point(10, 20);
  int nativeResult = 0;
  for (int i = 0; i < 10000; i++) {
    nativeResult += p.x + p.y + p.sum;
  }
  nativeWatch.stop();
  final nativeMs = nativeWatch.elapsedMicroseconds / 1000.0;
  print('  Native:    ${nativeMs.toStringAsFixed(2)}ms (result: $nativeResult)');
  print('');

  return {'dart_eval': evalMs, 'native': nativeMs};
}

class _Point {
  int x;
  int y;
  _Point(this.x, this.y);
  int get sum => x + y;
}

Map<String, double> benchmark5() {
  print('Benchmark 5: List operations (5000 elements)');
  print('-' * 60);

  final compiler = Compiler();
  final runtime = compiler.compileWriteAndLoad({
    'bench': {
      'main.dart': '''
        int main() {
          List<int> list = [];
          for (int i = 0; i < 5000; i++) {
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

  final evalWatch = Stopwatch()..start();
  final evalResult = runtime.executeLib('package:bench/main.dart', 'main');
  evalWatch.stop();
  final evalMs = evalWatch.elapsedMicroseconds / 1000.0;
  print('  dart_eval: ${evalMs.toStringAsFixed(2)}ms (result: $evalResult)');

  // Native Dart version
  final nativeWatch = Stopwatch()..start();
  List<int> list = [];
  for (int i = 0; i < 5000; i++) {
    list.add(i);
  }
  int nativeSum = 0;
  for (int i = 0; i < list.length; i++) {
    nativeSum += list[i];
  }
  nativeWatch.stop();
  final nativeMs = nativeWatch.elapsedMicroseconds / 1000.0;
  print('  Native:    ${nativeMs.toStringAsFixed(2)}ms (result: $nativeSum)');
  print('');

  return {'dart_eval': evalMs, 'native': nativeMs};
}

Map<String, double> benchmark6() {
  print('Benchmark 6: Collection iteration (1000 iterations, 10 elements)');
  print('-' * 60);

  final compiler = Compiler();
  final runtime = compiler.compileWriteAndLoad({
    'bench': {
      'main.dart': '''
        int main() {
          int sum = 0;
          for (int i = 0; i < 1000; i++) {
            List<int> list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
            for (int j = 0; j < list.length; j++) {
              sum += list[j];
            }
          }
          return sum;
        }
      '''
    }
  });

  final evalWatch = Stopwatch()..start();
  final evalResult = runtime.executeLib('package:bench/main.dart', 'main');
  evalWatch.stop();
  final evalMs = evalWatch.elapsedMicroseconds / 1000.0;
  print('  dart_eval: ${evalMs.toStringAsFixed(2)}ms (result: $evalResult)');

  // Native Dart version
  final nativeWatch = Stopwatch()..start();
  int nativeSum = 0;
  for (int i = 0; i < 1000; i++) {
    List<int> list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    for (int j = 0; j < list.length; j++) {
      nativeSum += list[j];
    }
  }
  nativeWatch.stop();
  final nativeMs = nativeWatch.elapsedMicroseconds / 1000.0;
  print('  Native:    ${nativeMs.toStringAsFixed(2)}ms (result: $nativeSum)');
  print('');

  return {'dart_eval': evalMs, 'native': nativeMs};
}
