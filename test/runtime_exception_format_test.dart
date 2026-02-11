import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeException formatting', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('RuntimeException includes frameOffsetStack', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              List<int> x = <int>[];
              return x[0];
            }
          '''
        }
      });
      try {
        runtime.executeLib('package:example/main.dart', 'main');
        fail('Should have thrown');
      } on RuntimeException catch (e) {
        final str = e.toString();
        expect(str, contains('frameOffsetStack:'));
      }
    });

    test('RuntimeException includes full scopeNameStack', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int deep() {
              List<int> x = <int>[];
              return x[0];
            }
            int mid() { return deep(); }
            int main() { return mid(); }
          '''
        }
      });
      try {
        runtime.executeLib('package:example/main.dart', 'main');
        fail('Should have thrown');
      } on RuntimeException catch (e) {
        final str = e.toString();
        expect(str, contains('Scope name stack:'));
        expect(str, contains('deep'));
        expect(str, contains('mid'));
        expect(str, contains('main'));
      }
    });

    test('RuntimeException does not crash when stack is empty', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() { return 1; }
          '''
        }
      });
      runtime.stack.clear();
      runtime.scopeNameStack.clear();

      final ex = RuntimeException(runtime, 'test error', StackTrace.current);
      final str = ex.toString();
      expect(str, contains('test error'));
      expect(str, contains('Stack sample: <empty>'));
    });
  });
}
