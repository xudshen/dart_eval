@Tags(['audit'])
import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Compiler-layer bug audit', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('CC-01: TypeRef static cache survives across compilations (simple)', () {
      // First compilation
      final compiler1 = Compiler();
      final runtime1 = compiler1.compileWriteAndLoad({
        'pkg1': {
          'main.dart': 'int main() { return 1; }',
        }
      });
      expect(runtime1.executeLib('package:pkg1/main.dart', 'main'), 1);

      // Second compilation with a different compiler instance
      // If TypeRef static cache leaks across compilations, this may fail
      final compiler2 = Compiler();
      final runtime2 = compiler2.compileWriteAndLoad({
        'pkg2': {
          'main.dart': 'int main() { return 2; }',
        }
      });
      expect(runtime2.executeLib('package:pkg2/main.dart', 'main'), 2);
    });

    test('CC-01: TypeRef static cache survives across compilations (same class names)',
        () {
      // Use the same class name in both packages to stress-test TypeRef
      // caching. If the static cache leaks, the second compilation may
      // resolve MyClass to the wrong type descriptor.
      final compiler1 = Compiler();
      final runtime1 = compiler1.compileWriteAndLoad({
        'pkg_a': {
          'main.dart': '''
            class MyClass {
              int value() { return 10; }
            }
            int main() {
              return MyClass().value();
            }
          '''
        }
      });
      expect(runtime1.executeLib('package:pkg_a/main.dart', 'main'), 10);

      final compiler2 = Compiler();
      final runtime2 = compiler2.compileWriteAndLoad({
        'pkg_b': {
          'main.dart': '''
            class MyClass {
              int value() { return 20; }
            }
            int main() {
              return MyClass().value();
            }
          '''
        }
      });
      expect(runtime2.executeLib('package:pkg_b/main.dart', 'main'), 20);
    });

    test('CC-03: Generic type arg not checked (List<String> assigned to List<int>)',
        () {
      // This code should be a type error: List<String> cannot be assigned
      // to List<int>. If the bug exists, the compiler silently accepts it.
      expect(
        () {
          compiler.compileWriteAndLoad({
            'eval_test': {
              'main.dart': '''
                List<int> main() {
                  List<String> strings = ['a', 'b'];
                  List<int> ints = strings;
                  return ints;
                }
              '''
            }
          });
        },
        throwsA(anything),
      ); // Expect a compile-time type error
    });

    test('CC-05: Constructor field formal overwritten by default value', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            class Foo {
              int x = 0;
              Foo(this.x);
            }
            int main() {
              final foo = Foo(42);
              return foo.x;
            }
          '''
        }
      });
      // Correct Dart semantics: foo.x should be 42, not the default 0
      expect(
          runtime.executeLib('package:eval_test/main.dart', 'main'), 42);
    });

    test('CC-04: Cross-library static function dispatch', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'helper.dart': '''
            int add(int a, int b) { return a + b; }
          ''',
          'main.dart': '''
            import 'helper.dart';
            int main() {
              return add(3, 4);
            }
          '''
        }
      });
      expect(
          runtime.executeLib('package:eval_test/main.dart', 'main'), 7);
    });

    test('RT-07: Global var initialized to null re-runs initializer (static field variant)',
        () {
      // A static field whose initializer returns null should only
      // be initialized once. If the runtime cannot distinguish "not yet
      // initialized" from "initialized to null", it will re-run the
      // initializer on every access.
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            class Counter {
              static int value = 0;
            }

            class NullHolder {
              static String? val = _doInit();

              static String? _doInit() {
                Counter.value = Counter.value + 1;
                return null;
              }
            }

            int main() {
              var a = NullHolder.val;
              var b = NullHolder.val;
              return Counter.value;
            }
          '''
        }
      });
      // Correct Dart semantics: initializer runs exactly once, counter = 1
      expect(
          runtime.executeLib('package:eval_test/main.dart', 'main'), 1);
    });

    test('RT-07: Global var initialized to null re-runs initializer (top-level variant)',
        () {
      // A top-level variable whose initializer returns null should only
      // be initialized once. The LoadGlobal opcode uses null as sentinel
      // for "uninitialized", so accessing a null-initialized global
      // re-runs its initializer every time.
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            int counter = 0;
            String? nullGlobal = _initNull();

            String? _initNull() {
              counter = counter + 1;
              return null;
            }

            int main() {
              var a = nullGlobal;
              var b = nullGlobal;
              return counter;
            }
          '''
        }
      });
      // Correct Dart semantics: initializer runs exactly once, counter = 1
      expect(
          runtime.executeLib('package:eval_test/main.dart', 'main'), 1);
    });

    test('RT-01: Concurrent async operations sharing runtime state', () async {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            Future<int> delayed(int ms, int val) async {
              await Future.delayed(Duration(milliseconds: ms));
              return val;
            }

            Future<int> main() async {
              final a = delayed(50, 1);
              final b = delayed(50, 2);
              final ra = await a;
              final rb = await b;
              return ra + rb;
            }
          '''
        }
      });
      final result =
          runtime.executeLib('package:eval_test/main.dart', 'main') as Future;
      // Correct Dart semantics: 1 + 2 = 3
      await expectLater(result, completion($int(3)));
    });
  });
}
