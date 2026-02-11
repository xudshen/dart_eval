import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('Bridge null safety (M-12)', () {
    test('Bridge programs still work after _bridgeData refactor', () {
      // A simple program that exercises the bridge (print uses bridge)
      final result = evalMain('''
        int main() {
          final list = [1, 2, 3];
          return list.length;
        }
      ''');
      expect(result, 3);
    });

    test('Class with bridge interaction works', () {
      final result = evalMain('''
        String main() {
          final s = 'hello world';
          return s.toUpperCase();
        }
      ''');
      expect((result as dynamic).$reified, 'HELLO WORLD');
    });
  });
}
