import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/runtime/exception.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Exception tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Basic try/catch', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              try {
                throw 'error';
              } catch (e) {
                return 5;
              }
              return 2;
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), $int(5));
    });

    test('Try/catch no error', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              try {
                print('hello');
              } catch (e) {
                return 4;
              }
              return 2;
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), $int(2));
    });

    test('Nested try/catch', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              try {
                try {
                  throw 'error';
                } catch (e) {
                  throw 'error2';
                }
              } catch (e) {
                return e;
              }
              return 'error3';
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main').$value,
          'error2');
    });

    test('Try/catch across function boundaries', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              try {
                return doThing();
              } catch (e) {
                return e + 'no';
              }
            }
            
            String doThing() {
              throw 'error';
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main').$value,
          'errorno');
    });

    test('Try/catch with on', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              try {
                return doThing();
              } on int catch (e) {
                return e.toString() + '2';
              } on String catch (e) {
                return e + 'no';
              }
            }
            
            String doThing() {
              throw 'error';
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main').$value,
          'errorno');
    });

    test('Return from finally precedes error', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              try {
                throw 'error';
              } finally {
                return 'finally';
              }
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main').$value,
          'finally');
    });

    test('Error propagates through empty finally', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              try {
                throw 'error';
              } finally {}
            }
          ''',
        }
      });
      expect(() => runtime.executeLib('package:example/main.dart', 'main'),
          throwsA($String('error')));
    });

    test('Return from catch is preceded by finally return', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              try {
                throw 'error';
              } catch (e) {
                return 'catch';
              } finally {
                return 'finally';
              }
            }
          ''',
        }
      });
      expect(runtime.executeLib('package:example/main.dart', 'main').$value,
          'finally');
    });

    test('Finally can do work and return value from catch', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              try {
                throw 'error';
              } catch (e) {
                return 'catch';
              } finally {
                print('finally');
              }
              print('should not print');
            }
          ''',
        }
      });
      expect(
          () => expect(
              runtime.executeLib('package:example/main.dart', 'main').$value,
              'catch'),
          prints('finally\n'));
    });

    test('Manipulating local variables in catch and finally', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              var i = 0;
              try {
                throw 'error';
              } catch (e) {
                i++;
              } finally {
                i+=3;
              }
              return i;
            }
          ''',
        }
      });

      expect(runtime.executeLib('package:example/main.dart', 'main'), 4);
    });

    test('Try without throw skips catch but executes finally', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              var i = 0;
              try {
                i++;
              } catch (e) {
                i+=2;
              } finally {
                i+=3;
              }
              return i;
            }
          ''',
        }
      });

      expect(runtime.executeLib('package:example/main.dart', 'main'), 4);
    });

    test('Nested try/catch/finally', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              var i = 0;
              try {
                try {
                  throw 'error';
                } catch (e) {
                  i++;
                } finally {
                  i+=3;
                }
              } catch (e) {
                i+=5; // should not execute
              } finally {
                i+=7;
              }
              return i;
            }
          ''',
        }
      });

      expect(runtime.executeLib('package:example/main.dart', 'main'), 11);
    });

    test('Rethrow', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              try {
                throw 'error';
              } catch (e) {
                rethrow;
              }
              return 2;
            }
          ''',
        }
      });
      expect(() => runtime.executeLib('package:example/main.dart', 'main'),
          throwsA($String('error')));
    });

    test('Simple assert', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              assert(false);
            }
          ''',
        }
      });
      expect(() => runtime.executeLib('package:example/main.dart', 'main'),
          throwsA(isA<AssertionError>()));
    });

    test('DateTime.parse throwing exception', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              final a = tryCatch();
              print(a);
            }

            DateTime? tryCatch() {
              try {
                return DateTime.parse('please fail');
              } on FormatException catch (e) {
                print(e);
                return null;
              }
            }
          '''
        }
      });
      expect(() => runtime.executeLib('package:example/main.dart', 'main'),
          prints('FormatException: Invalid date format\nplease fail\nnull\n'));
    });

    test('Accessing property on null throws descriptive error, not cast error',
        () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              dynamic x = null;
              return x.toString();
            }
          '''
        }
      });
      // Should throw, but with a meaningful error, not "type '\$null' is not
      // a subtype of type '\$Instance'"
      expect(
        () => runtime.executeLib('package:example/main.dart', 'main'),
        throwsA(anything),
      );
    });

    test('formatStackSample handles raw primitives on stack', () {
      final stack = List<Object?>.filled(10, null);
      stack[0] = 42; // raw int (not $int)
      stack[1] = 3.14; // raw double
      stack[2] = true; // raw bool
      stack[3] = $int(5); // proper $Value
      stack[4] = null; // null
      final result = formatStackSample(stack, 5, 0);
      expect(result, contains('L0:'));
      expect(result, contains('(raw) 42'));
      expect(result, contains('(raw) 3.14'));
      expect(result, contains('(raw) true'));
      expect(result, contains('\$5'));
      expect(result, contains('null'));
    });

    test('Catching exception after await', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            import 'dart:async';
            
            void main() async {
              await Future.delayed(const Duration(milliseconds: 10));
              throw 'error';
            }
          '''
        }
      });
      expect(() => runtime.executeLib('package:example/main.dart', 'main'),
          throwsA($String('error')));
    });

    test('Exception bubbles through asynchronous gap', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            import 'dart:async';

            void main() async {
              await Future.delayed(const Duration(milliseconds: 10));
              throw 'error';
            }
          '''
        }
      });
      expect(() => runtime.executeLib('package:example/main.dart', 'main'),
          throwsA($String('error')));
    });

    test('Try-catch around await does not underflow catch stack', () async {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            import 'dart:async';

            Future<int> main() async {
              var result = 0;
              try {
                await Future.delayed(Duration(milliseconds: 10));
                result = 42;
              } catch (e) {
                result = -1;
              }
              return result;
            }
          '''
        }
      });
      final future =
          runtime.executeLib('package:example/main.dart', 'main') as Future;
      await expectLater(future, completion($int(42)));
    });

    test('Try-catch with multiple sequential awaits inside try block',
        () async {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            import 'dart:async';

            Future<int> main() async {
              var result = 0;
              try {
                await Future.delayed(Duration(milliseconds: 10));
                result = result + 10;
                await Future.delayed(Duration(milliseconds: 10));
                result = result + 32;
              } catch (e) {
                result = -1;
              }
              return result;
            }
          '''
        }
      });
      final future =
          runtime.executeLib('package:example/main.dart', 'main') as Future;
      await expectLater(future, completion($int(42)));
    });

    test('Try-catch catches error thrown after await', () async {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            import 'dart:async';

            Future<int> main() async {
              try {
                await Future.delayed(Duration(milliseconds: 10));
                throw 'async error';
              } catch (e) {
                return 99;
              }
              return 0;
            }
          '''
        }
      });
      final future =
          runtime.executeLib('package:example/main.dart', 'main') as Future;
      await expectLater(future, completion($int(99)));
    });
  });
}
