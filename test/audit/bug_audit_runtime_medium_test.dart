@Tags(['audit'])
import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/shared/stdlib/core/base.dart';
import 'package:test/test.dart';

/// Bug audit tests for MEDIUM-severity runtime and stdlib issues.
///
/// Each test documents the bug ID, what the bug is, and whether the test
/// confirms or disproves the bug's existence.
///
/// Test results summary:
///   CONFIRMED bugs (5):
///     - SL-06: Stream.listen onDone/onError named params swapped
///     - SL-07: Stream.first/last/single return raw Future, not $Future
///     - SL-13: Stream.where/take/takeWhile/skipWhile not implemented
///     - SL-15: double.parse/tryParse declared but no runtime registration
///     - SL-32: Map.cast is a no-op (returns target unchanged) -- functional
///
///   NOT AFFECTED / WORKING (5):
///     - SL-09: String.contains() works correctly with String argument
///     - SL-16: List.removeAt works correctly (both direct and view)
///     - SL-27: DateTime.isAfter/isBefore produce correct results
///     - SL-30: String.fromCharCodes works correctly
///     - SL-32: Map.cast returns a usable map (no-op but functional)
///
///   SKIPPED (not testable via functional tests):
///     - RT-19: dead code ByteData allocation (no behavioral impact)
///     - RT-20: RuntimeTypeSet.== repeated DeepCollectionEquality (perf only)
///     - SL-11: $Iterable.$reified not recursively unwrapping (bridge-level)
///     - SL-23: $MapEntry.$reified not unwrapping (bridge-level)
///     - SL-27: $DateTime per-call $Function allocation (perf only)
///     - SL-28/29: unreachable dead code (no behavioral impact)
void main() {
  group('Stdlib MEDIUM bug audit', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    // =========================================================================
    // SL-06: Stream.listen named params onDone/onError are swapped
    // STATUS: CONFIRMED
    // =========================================================================
    // In $Stream._listen (stream.dart:864-877):
    //   final onDone = args[1] as EvalCallable?;   // <-- BUG: args[1] is onError
    //   final onError = args[2] as EvalCallable?;   // <-- BUG: args[2] is onDone
    //
    // But the bridge declaration (stream.dart:459-469) orders named params as:
    //   onError (args[1]), onDone (args[2]), cancelOnError (args[3])
    //
    // So the runtime delivers onError in args[1] and onDone in args[2],
    // but the implementation reads them swapped.
    test(
        'SL-06: Stream.listen onDone/onError swapped '
        '-- onDone callback should fire on stream completion', () async {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            import 'dart:async';
            Future<String> main() async {
              final controller = StreamController<int>();
              String result = 'pending';
              controller.stream.listen(
                (event) {},
                onDone: () {
                  result = 'done';
                },
              );
              await controller.close();
              await Future.delayed(Duration(milliseconds: 50));
              return result;
            }
          '''
        }
      });

      final future =
          runtime.executeLib('package:eval_test/main.dart', 'main') as Future;
      final result = await future;
      // BUG CONFIRMED: result is 'pending' because onDone callback was
      // assigned to the onError slot due to args[1]/args[2] swap.
      // Correct Dart semantics: result should be 'done'.
      expect(result, $String('pending'),
          reason: 'SL-06 CONFIRMED: onDone callback is swapped to onError '
              'position, so it never fires on stream completion');
    });

    // =========================================================================
    // SL-07: Stream.first/last/single return raw Future, not $Future
    // STATUS: CONFIRMED
    // =========================================================================
    // In $Stream.$getProperty (stream.dart:637-644):
    //   case 'first':  return $value.first as $Value;   // raw Future cast
    //   case 'last':   return $value.last as $Value;     // raw Future cast
    //   case 'single': return $value.single as $Value;   // raw Future cast
    //
    // Stream.first/last/single return Future<T>, which is NOT a $Value.
    // The `as $Value` cast throws TypeError at runtime.
    test(
        'SL-07: Stream.first returns raw Future causing TypeError', () async {
      Object? error;

      try {
        final runtime = compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              import 'dart:async';
              Future<int> main() async {
                final controller = StreamController<int>();
                controller.add(42);
                controller.close();
                return await controller.stream.first;
              }
            '''
          }
        });

        final future =
            runtime.executeLib('package:eval_test/main.dart', 'main') as Future;
        await future;
      } catch (e) {
        error = e;
      }

      // BUG CONFIRMED: throws "type 'Future<dynamic>' is not a subtype of
      // type '$Value' in type cast" because Stream.first returns raw Future,
      // not $Future.
      expect(error, isNotNull,
          reason: 'SL-07 CONFIRMED: Stream.first throws TypeError because '
              'it returns raw Future<dynamic> instead of \$Future');
      expect(error.toString(), contains("Future<dynamic>"),
          reason: 'SL-07: Error should mention Future<dynamic> cast failure');
    });

    // =========================================================================
    // SL-09: String.contains() works with String argument
    // STATUS: WORKING (String arg is fine; limitation is Pattern/RegExp only)
    // =========================================================================
    test('SL-09: String.contains() works with String argument', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              String s = 'hello world';
              bool r1 = s.contains('world');
              bool r2 = s.contains('xyz');
              bool r3 = s.contains('');
              return '\$r1,\$r2,\$r3';
            }
          '''
        }
      });

      expect(
        runtime.executeLib('package:eval_test/main.dart', 'main'),
        $String('true,false,true'),
        reason: 'SL-09: String.contains with String arg works correctly',
      );
    });

    // =========================================================================
    // SL-13: $Stream missing take/where/takeWhile/skipWhile in $getProperty
    // STATUS: CONFIRMED
    // =========================================================================
    // The bridge declaration includes 'take', 'where', 'takeWhile', 'skipWhile'
    // methods, but $getProperty switch (stream.dart:636-696) has NO cases for
    // them, and NO static implementation functions (__where, __take, etc.) exist.
    // Calling these methods falls through to default -> _superclass ($Object)
    // which returns null, causing NoSuchMethodError.
    test('SL-13: Stream.where is not implemented -- falls through to Object',
        () async {
      Object? error;

      try {
        final runtime = compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              import 'dart:async';
              Future<void> main() async {
                final controller = StreamController<int>();
                controller.add(1);
                controller.add(2);
                controller.add(3);
                final filtered = controller.stream.where((e) => e > 1);
                filtered.listen((event) {
                  print(event);
                });
                await controller.close();
                await Future.delayed(Duration(milliseconds: 50));
              }
            '''
          }
        });

        final future =
            runtime.executeLib('package:eval_test/main.dart', 'main') as Future;
        await future;
      } catch (e) {
        error = e;
      }

      // BUG CONFIRMED: Stream.where() is declared in bridge but has no
      // implementation, causing runtime error.
      expect(error, isNotNull,
          reason: 'SL-13 CONFIRMED: Stream.where() has no implementation, '
              'causing runtime error: $error');
    });

    // =========================================================================
    // SL-15: double.parse declared but no runtime implementation registered
    // STATUS: CONFIRMED
    // =========================================================================
    // $double.$declaration declares 'parse' and 'tryParse' methods, but in
    // core.dart configureForRuntime (lines 117-121) only registers:
    //   double.nan*g, double.infinity*g, double.negativeInfinity*g
    // double.parse and double.tryParse are NEVER registered.
    test('SL-15: double.parse has no runtime implementation', () {
      Object? error;

      try {
        final runtime = compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              double main() {
                return double.parse('3.14');
              }
            '''
          }
        });

        runtime.executeLib('package:eval_test/main.dart', 'main');
      } catch (e) {
        error = e;
      }

      // BUG CONFIRMED: Throws "Null check operator used on a null value"
      // because the bridge function is declared but never registered.
      expect(error, isNotNull,
          reason: 'SL-15 CONFIRMED: double.parse declared but never '
              'registered with registerBridgeFunc; error: $error');
    });

    test('SL-15: double.tryParse has no runtime implementation', () {
      Object? error;

      try {
        final runtime = compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              String main() {
                var a = double.tryParse('2.718');
                var b = double.tryParse('abc');
                return '\$a,\$b';
              }
            '''
          }
        });

        runtime.executeLib('package:eval_test/main.dart', 'main');
      } catch (e) {
        error = e;
      }

      // BUG CONFIRMED: Same root cause as double.parse -- not registered.
      expect(error, isNotNull,
          reason: 'SL-15 CONFIRMED: double.tryParse declared but never '
              'registered with registerBridgeFunc; error: $error');
    });

    // =========================================================================
    // SL-16: $_List$view._removeAt returns value without mapping
    // STATUS: WORKING (at least for basic cases)
    // =========================================================================
    // The _$List$view._removeAt returns raw value from the underlying list,
    // but for integer lists the internal representation already stores $int
    // values, so the return value happens to work.
    test('SL-16: List.removeAt returns correct value', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            int main() {
              var list = [10, 20, 30];
              var removed = list.removeAt(1);
              return removed;
            }
          '''
        }
      });

      final result =
          runtime.executeLib('package:eval_test/main.dart', 'main');
      expect(result, 20,
          reason: 'SL-16: removeAt works for basic int lists');
    });

    test('SL-16: List view removeAt returns correct value', () {
      Object? result;
      Object? error;

      try {
        final runtime = compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              int main() {
                var list = [1, 2, 3, 4, 5];
                var filtered = list.where((e) => true).toList();
                var removed = filtered.removeAt(0);
                return removed;
              }
            '''
          }
        });

        result = runtime.executeLib('package:eval_test/main.dart', 'main');
      } catch (e) {
        error = e;
      }

      expect(error, isNull,
          reason: 'SL-16: list view removeAt should not throw; error: $error');
      if (error == null) {
        expect(result, 1,
            reason: 'SL-16: removeAt(0) on [1,2,3,4,5] should return 1');
      }
    });

    // =========================================================================
    // SL-27: DateTime methods work correctly (isAfter/isBefore)
    // STATUS: WORKING (the bug is about performance, not correctness)
    // =========================================================================
    // The bug reports that $DateTime.$getProperty creates a new $Function on
    // every access. This is a performance/GC issue, not a correctness bug.
    // Methods still produce correct results.
    test('SL-27: DateTime.isAfter and isBefore produce correct results', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              var a = DateTime.parse('2024-01-15 00:00:00');
              var b = DateTime.parse('2024-06-20 00:00:00');
              bool r1 = b.isAfter(a);
              bool r2 = a.isBefore(b);
              bool r3 = a.isAfter(b);
              bool r4 = b.isBefore(a);
              return '\$r1,\$r2,\$r3,\$r4';
            }
          '''
        }
      });

      expect(
        runtime.executeLib('package:eval_test/main.dart', 'main'),
        $String('true,true,false,false'),
        reason: 'SL-27: DateTime comparison methods produce correct results '
            '(bug is perf-only, not correctness)',
      );
    });

    test('SL-27: DateTime constructor and property access', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              var dt = DateTime(2024, 3, 15, 10, 30);
              return '\${dt.year},\${dt.month},\${dt.day},\${dt.hour},\${dt.minute}';
            }
          '''
        }
      });

      expect(
        runtime.executeLib('package:eval_test/main.dart', 'main'),
        $String('2024,3,15,10,30'),
        reason: 'SL-27: DateTime properties accessible (perf bug only)',
      );
    });

    // =========================================================================
    // SL-30: String.fromCharCodes silently swallows exceptions
    // STATUS: WORKING for normal cases (bug is about error handling edge case)
    // =========================================================================
    // The bug says _fromCharCodes uses try/catch to parse the `end` parameter,
    // swallowing any exception. Normal usage without `end` works fine.
    test('SL-30: String.fromCharCodes produces correct string', () {
      Object? result;
      Object? error;

      try {
        final runtime = compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              String main() {
                return String.fromCharCodes([72, 101, 108, 108, 111]);
              }
            '''
          }
        });

        result = runtime.executeLib('package:eval_test/main.dart', 'main');
      } catch (e) {
        error = e;
      }

      expect(error, isNull,
          reason: 'SL-30: String.fromCharCodes normal case works; error: $error');
      if (error == null) {
        expect(result, $String('Hello'),
            reason: 'SL-30: fromCharCodes([72,101,108,108,111]) = "Hello"');
      }
    });

    test('SL-30: String.fromCharCodes with start parameter', () {
      Object? result;
      Object? error;

      try {
        final runtime = compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              String main() {
                return String.fromCharCodes([72, 101, 108, 108, 111], 2);
              }
            '''
          }
        });

        result = runtime.executeLib('package:eval_test/main.dart', 'main');
      } catch (e) {
        error = e;
      }

      expect(error, isNull,
          reason: 'SL-30: fromCharCodes with start works; error: $error');
      if (error == null) {
        expect(result, $String('llo'),
            reason: 'SL-30: fromCharCodes with start=2 produces "llo"');
      }
    });

    test('SL-30: String.fromCharCode produces correct character', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              return String.fromCharCode(65);
            }
          '''
        }
      });

      expect(
        runtime.executeLib('package:eval_test/main.dart', 'main'),
        $String('A'),
        reason: 'SL-30: fromCharCode(65) produces "A"',
      );
    });

    // =========================================================================
    // SL-32: Map.cast is a no-op (returns target unchanged)
    // STATUS: CONFIRMED (but functionally harmless for same-type casts)
    // =========================================================================
    // In $Map._cast (map.dart:199-201):
    //   static $Value? _cast(Runtime runtime, $Value? target, List<$Value?> args) {
    //     return target;
    //   }
    // This just returns the original map. For same-type casts it works, but
    // it violates the contract of Map.cast<RK, RV>() which should return a
    // new Map view with the casted types.
    test('SL-32: Map.cast returns a map (functionally a no-op)', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              Map<String, int> original = {'a': 1, 'b': 2};
              var casted = original.cast();
              return casted.keys.join(',');
            }
          '''
        }
      });

      // The no-op behavior happens to work for same-type access.
      expect(
        runtime.executeLib('package:eval_test/main.dart', 'main'),
        $String('a,b'),
        reason: 'SL-32: Map.cast no-op returns usable map (same-type OK)',
      );
    });
  });
}
