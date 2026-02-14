import 'dart:convert';
import 'dart:io';

import 'package:dart_eval/dart_eval.dart';
import 'package:test/test.dart';

import 'expect_plugin.dart';

/// Root path to the co19 submodule, relative to the dart_eval package root.
///
/// `dart test` always runs from the package root (`packages/dart_eval/`),
/// so this relative path resolves correctly.
const co19Root = '../../third_party/co19';

/// Default per-test timeout for co19 tests.
const co19Timeout = Timeout(Duration(seconds: 30));

/// Regex matching co19 Expect import (various quote styles and path depths).
final _expectImportPattern =
    RegExp(r'''import\s+(['"])\.\.[\./]*Utils/expect\.dart\1\s*;''');

/// Regex matching co19 dynamic_check / static_type_helper imports.
final _utilImportPattern =
    RegExp(r'''import\s+(['"])\.\.[\./]*Utils/\w+\.dart\1\s*;''');

/// Rewrite co19 imports for dart_eval consumption.
///
/// - `../Utils/expect.dart` → `package:co19_expect/expect.dart`
/// - `../Utils/dynamic_check.dart` etc. → removed
String transformSource(String source) {
  var result = source.replaceAll(
      _expectImportPattern, "import 'package:co19_expect/expect.dart';");
  result = result.replaceAll(
      _utilImportPattern, '// [co19_adapter] removed Utils import');
  return result;
}

/// Registers a single co19 test that reads, transforms, and executes a co19
/// source file through dart_eval.
///
/// Each call creates a fresh [Compiler] and [Runtime] for isolation.
void co19Test({
  required String group,
  required String name,
  required String path,
  Timeout timeout = co19Timeout,
}) {
  test('$group $name', () {
    final file = File('$co19Root/$path');
    if (!file.existsSync()) {
      fail('co19 source file not found: $co19Root/$path\n'
          'Make sure the co19 submodule is initialized: '
          'git submodule update --init');
    }

    final source = transformSource(file.readAsStringSync());

    final plugin = Co19ExpectPlugin();
    final compiler = Compiler();
    compiler.addPlugin(plugin);
    final runtime = compiler.compileWriteAndLoad({
      'co19_test': {'main.dart': source}
    });
    plugin.configureForRuntime(runtime);
    runtime.executeLib('package:co19_test/main.dart', 'main');
  }, timeout: timeout);
}

/// Reads a manifest.json and registers all co19 tests listed in it.
///
/// The manifest must contain:
/// - `group`: top-level group name (e.g., 'co19 Language/Expressions')
/// - `subDir`: co19 subdirectory (e.g., 'Language/Expressions')
/// - `entries`: list of co19-relative source paths
///
/// Tests are wrapped in a `group()` matching the manifest's group name.
void co19TestSuite({
  required String manifestPath,
  Timeout timeout = co19Timeout,
}) {
  final file = File(manifestPath);
  if (!file.existsSync()) {
    throw StateError('Manifest not found: $manifestPath\n'
        'Run: fvm dart tool/co19_adapter/adapt.dart <co19-subdir>');
  }

  final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final groupName = manifest['group'] as String;
  final subDir = manifest['subDir'] as String;
  final entries = (manifest['entries'] as List).cast<String>();

  group(groupName, () {
    for (final entry in entries) {
      // entry is co19-relative path: "Language/Expressions/Additive_Expressions/allowed_characters_t01.dart"
      // Strip subDir prefix to get test name: "Additive_Expressions > allowed_characters_t01"
      final name = entry
          .replaceFirst('$subDir/', '')
          .replaceAll('/', ' > ')
          .replaceAll('.dart', '');

      test(name, () {
        final file = File('$co19Root/$entry');
        if (!file.existsSync()) {
          fail('co19 source file not found: $co19Root/$entry\n'
              'Make sure the co19 submodule is initialized: '
              'git submodule update --init');
        }

        final source = transformSource(file.readAsStringSync());

        final plugin = Co19ExpectPlugin();
        final compiler = Compiler();
        compiler.addPlugin(plugin);
        final runtime = compiler.compileWriteAndLoad({
          'co19_test': {'main.dart': source}
        });
        plugin.configureForRuntime(runtime);
        runtime.executeLib('package:co19_test/main.dart', 'main');
      }, timeout: timeout);
    }
  });
}
