import 'package:test/test.dart';
import 'package:dart_eval/src/eval/bindgen/type.dart';

void main() {
  test('wrapVarSkipSentinel is a unique sentinel string', () {
    expect(wrapVarSkipSentinel, isNotEmpty);
    // Must not look like valid Dart code to prevent accidental emission
    expect(wrapVarSkipSentinel, startsWith('__SKIP__'));
  });
}
