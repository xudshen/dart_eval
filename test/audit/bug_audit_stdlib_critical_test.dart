@Tags(['audit'])
import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/shared/stdlib/core/base.dart';
import 'package:test/test.dart';

void main() {
  group('Stdlib CRITICAL bug audit', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('SL-01: List.sort() default comparator compares element with itself', () {
      // In Dart, [3, 1, 2].sort() should produce [1, 2, 3].
      // Bug: The default comparator in $List._sort uses args[0] for both
      // parameters instead of args[0] and args[1], so Comparable.compare(a, a)
      // always returns 0, leaving the list unsorted.
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              var list = [3, 1, 2];
              list.sort();
              return list.join(',');
            }
          '''
        }
      });

      // Correct Dart semantics: sorted ascending
      expect(
        runtime.executeLib('package:eval_test/main.dart', 'main'),
        $String('1,2,3'),
      );
    });

    test('SL-02: Iterable.toSet() returns \$List instead of \$Set (no dedup)', () {
      // In Dart, [1, 2, 2, 3, 3].toSet() should return {1, 2, 3} with length 3.
      // Bug: $Iterable._$toSet calls toList() and wraps in $List, so duplicates
      // are preserved and the result length is 5.
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            int main() {
              var list = [1, 2, 2, 3, 3];
              var s = list.toSet();
              return s.length;
            }
          '''
        }
      });

      // Correct Dart semantics: deduplication produces length 3
      expect(
        runtime.executeLib('package:eval_test/main.dart', 'main'),
        3,
      );
    });

    test('SL-03: \$Set.\$getRuntimeType returns CoreTypes.map instead of CoreTypes.set', () {
      // In Dart, a Set should pass `is Set` check.
      // Bug: $Set.$getRuntimeType returns runtime.lookupType(CoreTypes.map),
      // so the runtime type is Map instead of Set.
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              var mySet = {1, 2, 3};
              bool isSet = mySet is Set;
              return isSet.toString();
            }
          '''
        }
      });

      // Correct Dart semantics: a Set literal `is Set` should be true
      expect(
        runtime.executeLib('package:eval_test/main.dart', 'main'),
        $String('true'),
      );
    });

    test('SL-04: Set.add() returns null instead of bool', () {
      // In Dart, Set.add() returns true if the element was added (not present),
      // false if it was already there.
      // Bug: $Set._add returns null instead of $bool(result).
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            String main() {
              var s = <int>{};
              var result1 = s.add(1);
              var result2 = s.add(1);
              return '\$result1,\$result2';
            }
          '''
        }
      });

      // Correct Dart semantics: first add returns true, second returns false
      expect(
        runtime.executeLib('package:eval_test/main.dart', 'main'),
        $String('true,false'),
      );
    });

    test('SL-05: Set.from() only accepts Set, not Iterable (List)', () {
      // In Dart, Set.from() accepts any Iterable, including List.
      // Bug: __$Set$from casts args[0]?.$value as Set, but a List value
      // is not a Set, causing a TypeError at runtime.
      Object? result;
      Object? error;

      try {
        final runtime = compiler.compileWriteAndLoad({
          'eval_test': {
            'main.dart': '''
              String main() {
                var list = [1, 2, 3];
                var s = Set.from(list);
                return s.length.toString();
              }
            '''
          }
        });
        result = runtime.executeLib('package:eval_test/main.dart', 'main');
      } catch (e) {
        error = e;
      }

      // If bug exists, error will be non-null (TypeError casting List to Set).
      // Correct Dart semantics: Set.from([1,2,3]) should produce {1,2,3}
      expect(error, isNull, reason: 'Set.from(list) should not throw; got: $error');
      expect(result, $String('3'));
    });
  });
}
