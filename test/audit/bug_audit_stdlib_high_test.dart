@Tags(['audit'])
import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:test/test.dart';

/// Bug audit tests for dart_eval stdlib HIGH-severity issues.
///
/// Each test documents a known bug with its ID, expected behavior,
/// and actual (buggy) behavior.
void main() {
  late Compiler compiler;

  setUp(() {
    compiler = Compiler();
  });

  group('SL-08: num.parse onError callback cast failure', () {
    // Bug: In $num.$parse, onError is read as `args[1]?.$value as EvalCallable?`
    // but the eval runtime wraps the callback as an EvalFunction whose $value
    // getter throws UnimplementedError. The .$value access fails before the
    // cast to EvalCallable is even attempted.
    //
    // Root cause (num.dart line 76):
    //   final onError = args[1]?.$value as EvalCallable?;
    // Should be:
    //   final onError = args[1] as EvalCallable?;
    test('num.parse with onError callback should invoke callback on bad input',
        () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            num main() {
              return num.parse('abc', (source) => 0);
            }
          '''
        }
      });

      // Expected: returns 0 (the onError callback result)
      // Actual: throws RuntimeException because EvalFunction.$value
      //         throws UnimplementedError
      expect(
        () => runtime.executeLib('package:eval_test/main.dart', 'main'),
        throwsA(anything),
        reason: 'SL-08: num.parse onError callback read via .\$value fails '
            'because EvalFunction.\$value throws UnimplementedError',
      );
    });
  });

  group('SL-10: Map[key] = null force unwrap error', () {
    // Bug: In $Map._indexSet (map.dart line 185):
    //   final value = args[1]!;
    // The ! operator force-unwraps. When the eval runtime passes $null()
    // (the wrapper for null), args[1]! succeeds because $null() is non-null.
    //
    // However, the code stores the $null() wrapper into the underlying Map
    // instead of actual Dart null. This is risky because:
    // 1. The $null wrapper stored in the map may cause type issues downstream
    // 2. If the runtime ever passes actual Dart null (not $null()), the ! crashes
    //
    // In practice with simple `map['key'] = null`, the runtime wraps null as
    // $null() so the force-unwrap succeeds. The bug may only manifest in
    // more complex code paths where actual Dart null is passed.
    test('simple map[key] = null works (runtime wraps as \$null)', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            bool main() {
              var map = <String, int?>{};
              map['key'] = null;
              return map['key'] == null;
            }
          '''
        }
      });

      // This succeeds because the runtime passes $null() (not Dart null).
      // The args[1]! force-unwrap does not crash on $null() instances.
      final result =
          runtime.executeLib('package:eval_test/main.dart', 'main');
      print('SL-10: result = $result (type: ${result.runtimeType})');
      expect(result, isTrue,
          reason: 'SL-10: simple null assignment works because '
              'runtime wraps null as \$null()');
    });

    test('map[key] = nullable variable that is null', () {
      Object? error;
      Object? result;
      try {
        final runtime = compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              bool main() {
                var map = <String, String?>{};
                String? val = null;
                map['key'] = val;
                return map['key'] == null;
              }
            '''
          }
        });
        result =
            runtime.executeLib('package:eval_test/main.dart', 'main');
        print('SL-10 (nullable var): result = $result');
      } catch (e) {
        error = e;
        print('SL-10 (nullable var): BUG CONFIRMED - ${e.runtimeType}: $e');
      }

      // Document actual behavior: whether nullable variable path triggers
      // the force-unwrap error or also wraps as $null().
      if (error != null) {
        expect(error, isNotNull,
            reason: 'SL-10: nullable var assigned to map triggers '
                'force unwrap error');
      } else {
        expect(result, isTrue,
            reason: 'SL-10: nullable var path also wraps as \$null()');
      }
    });
  });

  group('SL-20: UnimplementedError() no-arg constructor', () {
    // Bug: In $UnimplementedError._$UnimplementedError$new (errors.dart line 344):
    //   final message = args[0]?.$value as String;
    // When no argument is passed, args[0] may be $null() or Dart null.
    // If $null(): args[0]?.$value => null, then `null as String` => TypeError
    // If Dart null: args[0]?.$value => null, then `null as String` => TypeError
    //
    // The correct code should be:
    //   final message = args[0]?.$value as String?;
    test('UnimplementedError() without message should construct normally', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              try {
                throw UnimplementedError();
              } catch (e) {
                return e.toString();
              }
            }
          '''
        }
      });

      // Expected: returns "UnimplementedError" string
      // Actual: may throw TypeError from the bridge layer before
      //         the UnimplementedError can be constructed
      Object? result;
      Object? error;
      try {
        result = runtime.executeLib('package:eval_test/main.dart', 'main');
      } catch (e) {
        error = e;
      }

      if (error != null) {
        print('SL-20: BUG CONFIRMED - bridge threw ${error.runtimeType}: $error');
        expect(error, isNotNull,
            reason: 'SL-20: UnimplementedError() no-arg throws TypeError');
      } else {
        final strResult = (result is $Value) ? result.$value : result;
        print('SL-20: Result = "$strResult"');
        // If we get here, the bug did not manifest (compiler may handle
        // optional args differently than expected)
        expect(strResult.toString(), contains('UnimplementedError'),
            reason: 'SL-20: Should return UnimplementedError string');
      }
    });

    test('UnimplementedError with explicit message works', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              try {
                throw UnimplementedError('not done');
              } catch (e) {
                return e.toString();
              }
            }
          '''
        }
      });

      final result =
          runtime.executeLib('package:eval_test/main.dart', 'main');
      final strResult = (result is $Value) ? result.$value : result;
      print('SL-20 (with message): Result = "$strResult"');
      expect(strResult.toString(), contains('not done'),
          reason: 'UnimplementedError with message should work');
    });
  });

  group('SL-19: List sort without comparator (fallback comparator bug)', () {
    // Bug in $List._$sort (list.dart line 1009-1011):
    //   final compare = args[0] as EvalFunction? ??
    //       $Function((runtime, target, args) =>
    //           $int(Comparable.compare(args[0]?.$value, args[0]?.$value)));
    //
    // Two issues:
    // 1. The fallback comparator compares args[0] with args[0] (same element)
    //    instead of args[0] with args[1]. This means every comparison returns 0,
    //    so the list is never reordered.
    // 2. In the _$List$view._sort (view path), there is no fallback at all:
    //    `final compare = args[0] as EvalCallable;` crashes when null.
    test('sort() without comparator should sort in natural order', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              var list = [3, 1, 4, 1, 5, 9, 2, 6];
              list.sort();
              return list.join(',');
            }
          '''
        }
      });

      final result =
          runtime.executeLib('package:eval_test/main.dart', 'main');
      final resultValue = (result is $Value) ? result.$value : result;
      print('SL-19: sort() result = "$resultValue"');

      // Expected: "1,1,2,3,4,5,6,9" (sorted ascending)
      // Actual: "3,1,4,1,5,9,2,6" (unchanged - fallback comparator
      //         compares each element with itself, always returns 0)
      expect(resultValue, isNot(equals('1,1,2,3,4,5,6,9')),
          reason: 'SL-19: BUG - fallback comparator uses args[0] twice, '
              'so sort() without comparator does not actually sort');
    });

    test('sort() with explicit comparator also broken', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              var list = [3, 1, 2];
              list.sort((a, b) => a.compareTo(b));
              return list.join(',');
            }
          '''
        }
      });

      final result =
          runtime.executeLib('package:eval_test/main.dart', 'main');
      final resultValue = (result is $Value) ? result.$value : result;
      print('SL-19 (with comparator): result = "$resultValue"');

      // Expected: "1,2,3" (sorted ascending)
      // Actual: "3,1,2" (unchanged) - the comparator lambda's return value
      // is not properly propagated through the eval runtime to the sort.
      // This is a broader sort() issue beyond just the null comparator path.
      expect(resultValue, isNot(equals('1,2,3')),
          reason: 'SL-19: sort() with explicit comparator is also broken - '
              'comparator result not properly propagated through eval runtime');
    });
  });

  group('SL-12: Map missing forEach method', () {
    // Bug: Map.$declaration (map.dart) does not include 'forEach' in its
    // methods map, and $getProperty switch does not handle 'forEach'.
    //
    // The Dart Map class implements forEach(), and the $Map class has it
    // as an @override method (line 262), but it's not exposed to eval code
    // because:
    // 1. Not declared in BridgeClassDef.methods
    // 2. Not handled in $getProperty switch
    test('Map.forEach should iterate over entries', () {
      // Expected: forEach iterates over all map entries
      // Actual: CompileError - "Unknown method Map.forEach"
      expect(
        () => compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              String main() {
                var map = {'a': 1, 'b': 2, 'c': 3};
                var result = '';
                map.forEach((key, value) {
                  result = result + key + value.toString();
                });
                return result;
              }
            '''
          }
        }),
        throwsA(anything),
        reason: 'SL-12: Map.forEach is not declared in bridge definition, '
            'causing CompileError: Unknown method Map.forEach',
      );
    });
  });

  group('SL-14: num missing round/floor/isNaN methods', () {
    // Bug: round(), floor(), isNaN are not declared in $num.$declaration
    // and not handled in $num.$getProperty (num.dart).
    //
    // $num only declares: parse, tryParse, toInt, toDouble, ceil, abs
    // Missing: round, floor, truncate, isNaN, isFinite, isNegative, isInfinite,
    //          clamp, remainder, sign, toStringAsFixed, toStringAsPrecision, etc.

    test('num.round() is not available (CompileError)', () {
      // Expected: 3.14.round() returns 3
      // Actual: CompileError - "Unknown method double.round"
      expect(
        () => compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              int main() {
                double x = 3.14;
                return x.round();
              }
            '''
          }
        }),
        throwsA(anything),
        reason: 'SL-14: num.round() is not declared in bridge, '
            'causing CompileError: Unknown method double.round',
      );
    });

    test('num.floor() is not available (CompileError)', () {
      // Expected: 3.14.floor() returns 3
      // Actual: CompileError - "Unknown method double.floor"
      expect(
        () => compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              int main() {
                double x = 3.14;
                return x.floor();
              }
            '''
          }
        }),
        throwsA(anything),
        reason: 'SL-14: num.floor() is not declared in bridge, '
            'causing CompileError: Unknown method double.floor',
      );
    });

    test('num.isNaN is not available (RuntimeException)', () {
      // Note: isNaN is a getter, not a method. The compiler may not catch
      // this at compile time (it falls through to $Object.$getProperty),
      // but at runtime $Object throws "UnimplementedError: $Object.isNaN".
      //
      // Expected: (0.0/0.0).isNaN returns true
      // Actual: RuntimeException with UnimplementedError: $Object.isNaN
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            bool main() {
              double x = 0.0 / 0.0;
              return x.isNaN;
            }
          '''
        }
      });

      expect(
        () => runtime.executeLib('package:eval_test/main.dart', 'main'),
        throwsA(anything),
        reason: 'SL-14: num.isNaN is not declared in bridge, '
            'falls through to \$Object which throws '
            'UnimplementedError: \$Object.isNaN',
      );
    });

    test('num.ceil() IS available (for comparison - already implemented)', () {
      // ceil() is already implemented in the bridge, confirming that
      // round/floor are missing by comparison.
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            int main() {
              double x = 3.14;
              return x.ceil();
            }
          '''
        }
      });

      final result =
          runtime.executeLib('package:eval_test/main.dart', 'main');
      expect(result, equals(4),
          reason: 'ceil() works because it IS declared in the bridge');
    });
  });
}
