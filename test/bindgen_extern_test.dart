import 'dart:io';

import 'package:dart_eval/src/eval/bindgen/bindgen.dart';
import 'package:dart_eval/src/eval/cli/utils.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  group('Bindgen @Bind.extern', () {
    late String output;

    setUpAll(() async {
      final bindgen = Bindgen();
      final fixtureRoot = Directory(
        join(Directory.current.path, 'test', 'fixtures', 'extern_test_sdk'),
      );

      // Load package config and inject the test package
      final packageConfig = getPackageConfig(fixtureRoot);
      for (final package in packageConfig.packages) {
        bindgen.inject(package: package);
      }

      // Parse the test source file
      final sourceFile =
          File(join(fixtureRoot.path, 'lib', 'test_sdk.dart'));
      final result = await bindgen.parse(
        sourceFile,
        'test_sdk.dart',
        'package:extern_test_sdk/test_sdk.dart',
        false, // not --all
      );

      expect(result, isNotNull,
          reason: 'Bindgen should produce output for @Bind-annotated class');
      output = result!;
    });

    test('extern getter "current" appears in \$declaration (compile-time)', () {
      // The $declaration BridgeClassDef should list 'current' as a getter
      // so that the compiler knows the member exists
      expect(output, contains("'current'"),
          reason: 'Extern getter should appear in \$declaration getters');
    });

    test('extern getter "current" is NOT in configureForRuntime', () {
      // configureForRuntime should NOT register the extern getter
      // The runtime registration format is: 'ClassName.memberName*g'
      expect(output, isNot(contains("'TestSdk.current*g'")),
          reason:
              'Extern getter should not be registered in configureForRuntime');
    });

    test('no \$current wrapper function generated for extern getter', () {
      // The static wrapper function $current should not be generated
      expect(output, isNot(contains(r'static $Value? $current(')),
          reason:
              'Extern getter should not have a wrapper function generated');
    });

    test('non-extern static method "hello" IS registered in runtime', () {
      // Normal (non-extern) members should still get runtime registration
      expect(output, contains("'TestSdk.hello'"),
          reason:
              'Non-extern static method should be registered in configureForRuntime');
    });

    test('non-extern static method "hello" has wrapper function', () {
      // Normal members should have their $-prefixed wrapper generated
      expect(output, contains(r'static $Value? $hello('),
          reason: 'Non-extern static method should have a wrapper function');
    });

    test('constructor is still registered in runtime', () {
      // Constructors should not be affected by extern at all
      expect(output, contains("'TestSdk.'"),
          reason: 'Constructor should still be registered in runtime');
    });
  });
}
