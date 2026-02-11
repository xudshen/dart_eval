import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/compiler/debug/scope_dump.dart';
import 'package:test/test.dart';

void main() {
  group('Scope tree dump', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Simple function shows variable-to-slot mapping', () {
      final recorder = ScopeRecorder();
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              int x = 10;
              int y = 20;
              return x + y;
            }
          '''
        }
      }, scopeRecorder: recorder);

      final dump = recorder.dump();
      expect(dump, contains('x'));
      expect(dump, contains('y'));
      expect(dump, contains('slot'));
      expect(runtime.executeLib('package:example/main.dart', 'main'), 30);
    });

    test('Closure shows #prev and captured variables', () {
      final recorder = ScopeRecorder();
      compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              int outer = 5;
              var fn = () { return outer; };
              return fn();
            }
          '''
        }
      }, scopeRecorder: recorder);

      final dump = recorder.dump();
      expect(dump, contains('#prev'));
      expect(dump, contains('outer'));
      expect(dump, contains('closure'));
    });

    test('Nested closures show multi-level #prev chain', () {
      final recorder = ScopeRecorder();
      compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void setState(void Function() fn) { fn(); }
            int main() {
              int x = 0;
              var callback = () {
                int val = 42;
                setState(() {
                  x = val;
                });
              };
              callback();
              return x;
            }
          '''
        }
      }, scopeRecorder: recorder);

      final dump = recorder.dump();
      expect(dump, contains('closure boundary'));
    });

    test('For loop scope shows per-iteration variables', () {
      final recorder = ScopeRecorder();
      compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              int sum = 0;
              for (int i = 0; i < 3; i = i + 1) {
                int temp = i;
                sum = sum + temp;
              }
              return sum;
            }
          '''
        }
      }, scopeRecorder: recorder);

      final dump = recorder.dump();
      expect(dump, contains('i'));
      expect(dump, contains('temp'));
    });
  });
}
