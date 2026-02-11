import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Stream methods', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Stream.where filters events', () {
      final runtime = compiler.compileWriteAndLoad({
        'stream_test': {
          'main.dart': '''
            import 'dart:async';

            Future main() async {
              final controller = StreamController<int>();
              controller.stream.where((x) => x > 2).listen((x) {
                print(x);
              });
              controller.add(1);
              controller.add(3);
              controller.add(2);
              controller.add(5);
              await controller.close();
            }
          '''
        }
      });
      expect(() async {
        await runtime
            .executeLib('package:stream_test/main.dart', 'main')
            .$value;
      }, prints('3\n5\n'));
    });

    test('Stream.take limits events', () {
      final runtime = compiler.compileWriteAndLoad({
        'stream_test': {
          'main.dart': '''
            import 'dart:async';

            Future main() async {
              final controller = StreamController<int>();
              controller.stream.take(2).listen((x) {
                print(x);
              });
              controller.add(10);
              controller.add(20);
              controller.add(30);
              await controller.close();
            }
          '''
        }
      });
      expect(() async {
        await runtime
            .executeLib('package:stream_test/main.dart', 'main')
            .$value;
      }, prints('10\n20\n'));
    });

    test('Stream.takeWhile takes while condition true', () {
      final runtime = compiler.compileWriteAndLoad({
        'stream_test': {
          'main.dart': '''
            import 'dart:async';

            Future main() async {
              final controller = StreamController<int>();
              controller.stream.takeWhile((x) => x < 4).listen((x) {
                print(x);
              });
              controller.add(1);
              controller.add(2);
              controller.add(3);
              controller.add(4);
              controller.add(5);
              await controller.close();
            }
          '''
        }
      });
      expect(() async {
        await runtime
            .executeLib('package:stream_test/main.dart', 'main')
            .$value;
      }, prints('1\n2\n3\n'));
    });

    test('Stream.skipWhile skips while condition true', () {
      final runtime = compiler.compileWriteAndLoad({
        'stream_test': {
          'main.dart': '''
            import 'dart:async';

            Future main() async {
              final controller = StreamController<int>();
              controller.stream.skipWhile((x) => x < 3).listen((x) {
                print(x);
              });
              controller.add(1);
              controller.add(2);
              controller.add(3);
              controller.add(4);
              controller.add(5);
              await controller.close();
            }
          '''
        }
      });
      expect(() async {
        await runtime
            .executeLib('package:stream_test/main.dart', 'main')
            .$value;
      }, prints('3\n4\n5\n'));
    });
  });
}
