import 'package:dart_eval/dart_eval.dart';
import 'package:test/test.dart';

void main() {
  group('CallFrame', () {
    test('default constructor creates empty catchOffsets', () {
      final frame = CallFrame(42);
      expect(frame.returnAddress, 42);
      expect(frame.catchOffsets, isEmpty);
    });

    test('constructor with catchOffsets', () {
      final frame = CallFrame(-1, [10, 20]);
      expect(frame.returnAddress, -1);
      expect(frame.catchOffsets, [10, 20]);
    });

    test('catchOffsets is mutable', () {
      final frame = CallFrame(0);
      frame.catchOffsets.add(5);
      frame.catchOffsets.add(-10);
      expect(frame.catchOffsets, [5, -10]);
      frame.catchOffsets.removeLast();
      expect(frame.catchOffsets, [5]);
    });

    test('toString includes return address and catches', () {
      final frame = CallFrame(100, [5, 10]);
      expect(frame.toString(), contains('100'));
      expect(frame.toString(), contains('[5, 10]'));
    });
  });

  group('Runtime callFrames integration', () {
    test('simple function call and return', () {
      final compiler = Compiler();
      final program = compiler.compile({
        'example': {
          'main.dart': '''
            int add(int a, int b) {
              return a + b;
            }
            int main() {
              return add(2, 3);
            }
          '''
        }
      });
      final runtime = Runtime.ofProgram(program);
      final result =
          runtime.executeLib('package:example/main.dart', 'main');
      expect(result, 5);
      // After execution, callFrames should be empty (all frames popped)
      expect(runtime.callFrames, isEmpty);
    });

    test('try-catch uses callFrames correctly', () {
      final compiler = Compiler();
      final program = compiler.compile({
        'example': {
          'main.dart': '''
            int main() {
              try {
                throw 'error';
              } catch (e) {
                return 42;
              }
            }
          '''
        }
      });
      final runtime = Runtime.ofProgram(program);
      final result =
          runtime.executeLib('package:example/main.dart', 'main');
      expect(result, 42);
      expect(runtime.callFrames, isEmpty);
    });

    test('nested function calls unwind correctly', () {
      final compiler = Compiler();
      final program = compiler.compile({
        'example': {
          'main.dart': '''
            int inner() {
              return 10;
            }
            int middle() {
              return inner() + 5;
            }
            int main() {
              return middle() + 1;
            }
          '''
        }
      });
      final runtime = Runtime.ofProgram(program);
      final result =
          runtime.executeLib('package:example/main.dart', 'main');
      expect(result, 16);
      expect(runtime.callFrames, isEmpty);
    });

    test('exception propagation across call frames', () {
      final compiler = Compiler();
      final program = compiler.compile({
        'example': {
          'main.dart': '''
            int thrower() {
              throw 'boom';
            }
            int main() {
              try {
                return thrower();
              } catch (e) {
                return -1;
              }
            }
          '''
        }
      });
      final runtime = Runtime.ofProgram(program);
      final result =
          runtime.executeLib('package:example/main.dart', 'main');
      expect(result, -1);
      expect(runtime.callFrames, isEmpty);
    });

    test('try-catch-finally uses callFrames correctly', () {
      final compiler = Compiler();
      final program = compiler.compile({
        'example': {
          'main.dart': '''
            int main() {
              var i = 0;
              try {
                i++;
              } catch (e) {
                i += 2;
              } finally {
                i += 3;
              }
              return i;
            }
          '''
        }
      });
      final runtime = Runtime.ofProgram(program);
      final result =
          runtime.executeLib('package:example/main.dart', 'main');
      expect(result, 4);
      expect(runtime.callFrames, isEmpty);
    });
  });
}
