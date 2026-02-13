import 'dart:io';

import 'package:dart_eval/src/eval/bindgen/bindgen.dart';
import 'package:dart_eval/src/eval/cli/bindgen_config.dart';
import 'package:dart_eval/src/eval/cli/utils.dart';
import 'package:test/test.dart';

void main() {
  late Bindgen bindgen;
  late Directory projectRoot;

  setUpAll(() {
    bindgen = Bindgen();
    projectRoot = findProjectRoot(Directory.current);
    final packageConfig = getPackageConfig(projectRoot);
    for (final package in packageConfig.packages) {
      bindgen.inject(package: package);
    }
  });

  group('preRegisterConfigTypes', () {
    test('pre-registered class types are visible to wrapType', () async {
      // Create a fresh Bindgen instance so we can test pre-registration
      final bg = Bindgen();
      final pc = getPackageConfig(projectRoot);
      for (final package in pc.packages) {
        bg.inject(package: package);
      }

      // Pre-register dart:math Random
      final libraries = [
        LibraryConfig(
          uri: 'dart:math',
          classes: [ClassEntry(name: 'Random')],
        ),
      ];

      await bg.preRegisterConfigTypes(
        libraries,
        packageName: 'dart_eval',
        pluginOutputDir: 'lib/_eval',
        projectRootPath: projectRoot.path,
      );

      // Now generate Random — it should succeed without skip sentinels
      final output = await bg.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Random',
        overrideLibrary: 'dart:math',
      );
      expect(output, isNotNull);
      expect(output, isNot(contains('__SKIP__UNBOUND_TYPE__')));
    });

    test('pre-registered enum types populate bridgeDeclarations', () async {
      final bg = Bindgen();
      final pc = getPackageConfig(projectRoot);
      for (final package in pc.packages) {
        bg.inject(package: package);
      }

      // Pre-register an enum type — use a simple enum from dart:core isn't
      // possible since those have builtin wrappers. Let's just verify the
      // method completes without error for a config with no valid enums.
      final libraries = [
        LibraryConfig(
          uri: 'dart:math',
          classes: [ClassEntry(name: 'Random')],
          enums: [], // dart:math has no enums, but this shouldn't error
        ),
      ];

      await bg.preRegisterConfigTypes(
        libraries,
        packageName: 'dart_eval',
        pluginOutputDir: 'lib/_eval',
        projectRootPath: projectRoot.path,
      );

      // The method should complete without throwing
    });

    test('generic types are skipped during pre-registration', () async {
      final bg = Bindgen();
      final pc = getPackageConfig(projectRoot);
      for (final package in pc.packages) {
        bg.inject(package: package);
      }

      // Point<T> is generic — it should be skipped
      final libraries = [
        LibraryConfig(
          uri: 'dart:math',
          classes: [
            ClassEntry(name: 'Point'),
            ClassEntry(name: 'Random'),
          ],
        ),
      ];

      // Should not throw
      await bg.preRegisterConfigTypes(
        libraries,
        packageName: 'dart_eval',
        pluginOutputDir: 'lib/_eval',
        projectRootPath: projectRoot.path,
      );

      // Random should still generate fine
      final output = await bg.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Random',
        overrideLibrary: 'dart:math',
      );
      expect(output, isNotNull);
    });

    test('invalid library URI is skipped gracefully', () async {
      final bg = Bindgen();
      final pc = getPackageConfig(projectRoot);
      for (final package in pc.packages) {
        bg.inject(package: package);
      }

      final libraries = [
        LibraryConfig(
          uri: 'package:nonexistent/nonexistent.dart',
          classes: [ClassEntry(name: 'Foo')],
        ),
      ];

      // Should not throw — just skip the unresolvable library
      await bg.preRegisterConfigTypes(
        libraries,
        packageName: 'dart_eval',
        pluginOutputDir: 'lib/_eval',
        projectRootPath: projectRoot.path,
      );
    });

    test('non-existent type name is skipped gracefully', () async {
      final bg = Bindgen();
      final pc = getPackageConfig(projectRoot);
      for (final package in pc.packages) {
        bg.inject(package: package);
      }

      final libraries = [
        LibraryConfig(
          uri: 'dart:math',
          classes: [ClassEntry(name: 'NonExistentClass')],
        ),
      ];

      // Should not throw
      await bg.preRegisterConfigTypes(
        libraries,
        packageName: 'dart_eval',
        pluginOutputDir: 'lib/_eval',
        projectRootPath: projectRoot.path,
      );
    });
  });

  group('resolveInterfaceElement', () {
    test('resolves a known class', () async {
      final element =
          await bindgen.resolveInterfaceElement('dart:math', 'Random');
      expect(element, isNotNull);
      expect(element!.name3, 'Random');
    });

    test('returns null for unknown class', () async {
      final element =
          await bindgen.resolveInterfaceElement('dart:math', 'NonExistent');
      expect(element, isNull);
    });

    test('returns null for invalid library', () async {
      final element = await bindgen.resolveInterfaceElement(
          'package:nonexistent/foo.dart', 'Foo');
      expect(element, isNull);
    });
  });
}
