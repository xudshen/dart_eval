import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Typedef / Type aliases', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Function type alias', () {
      final runtime = compiler.compileWriteAndLoad({
        'typedef_test': {
          'main.dart': '''
            typedef IntMapper = int Function(int);

            int applyMapper(IntMapper mapper, int value) {
              return mapper(value);
            }

            int main() {
              return applyMapper((x) => x * 2, 21);
            }
          '''
        }
      });
      expect(runtime.executeLib('package:typedef_test/main.dart', 'main'), 42);
    });

    test('Simple type alias', () {
      final runtime = compiler.compileWriteAndLoad({
        'typedef_test': {
          'main.dart': '''
            typedef StringList = List<String>;

            int main() {
              StringList names = ['Alice', 'Bob'];
              return names.length;
            }
          '''
        }
      });
      expect(runtime.executeLib('package:typedef_test/main.dart', 'main'), 2);
    });

    test('Callback typedef', () {
      final runtime = compiler.compileWriteAndLoad({
        'typedef_test': {
          'main.dart': '''
            typedef VoidCallback = void Function();

            int counter = 0;
            void increment() { counter = counter + 1; }

            void callTwice(VoidCallback fn) {
              fn();
              fn();
            }

            int main() {
              callTwice(increment);
              return counter;
            }
          '''
        }
      });
      expect(runtime.executeLib('package:typedef_test/main.dart', 'main'), 2);
    });
  });
}
