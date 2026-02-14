// CLI entry point: filter + transform + generate co19 tests for dart_eval.
//
// Usage:
//   fvm dart tool/co19_adapter/adapt.dart [--co19-root <path>] <co19-subdir>
//
// Example:
//   fvm dart tool/co19_adapter/adapt.dart Language/Expressions

import 'dart:convert';
import 'dart:io';

import 'filter.dart';
import 'transformer.dart';

void main(List<String> args) {
  var co19Root = '../../third_party/co19';
  String? subDir;

  // Parse args.
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--co19-root' && i + 1 < args.length) {
      co19Root = args[++i];
    } else if (args[i] == '--help' || args[i] == '-h') {
      _printUsage();
      exit(0);
    } else if (!args[i].startsWith('-')) {
      subDir = args[i];
    }
  }

  if (subDir == null) {
    _printUsage();
    exit(1);
  }

  final inputDir = '$co19Root/$subDir';
  if (!Directory(inputDir).existsSync()) {
    print('Error: directory does not exist: $inputDir');
    exit(1);
  }

  print('Scanning $inputDir ...');

  // Phase 1: Filter.
  final report = scanDirectory(inputDir);
  print(report);

  // Phase 2: Transform included files.
  final included =
      report.results.where((r) => r.status == FilterStatus.included).toList();

  final testEntries = <MapEntry<String, String>>[];
  var transformFailed = 0;

  for (final result in included) {
    final file = File('$inputDir${result.path}');
    final source = file.readAsStringSync();
    final transformed = transformSource(source);
    if (transformed == null) {
      transformFailed++;
      continue;
    }
    // Use relative path as test name.
    final testName = result.path
        .replaceFirst('/', '')
        .replaceAll('/', ' > ')
        .replaceAll('.dart', '');
    testEntries.add(MapEntry(testName, transformed));
  }

  print('\nTransform results:');
  print('  Included by filter: ${included.length}');
  print('  Successfully transformed: ${testEntries.length}');
  print('  Transform failed (relative imports): $transformFailed');

  if (testEntries.isEmpty) {
    print('\nNo tests to generate.');
    exit(0);
  }

  // Phase 3: Generate test file.
  // Convert subDir to a safe directory/file name.
  final safeName = subDir
      .replaceAll('/', '_')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
      .toLowerCase();
  final outputDir = 'test/co19/$safeName';
  final outputFile = '$outputDir/generated_test.dart';

  Directory(outputDir).createSync(recursive: true);

  final groupName = 'co19 $subDir';
  final testFileContent = generateTestFile(groupName, testEntries);
  File(outputFile).writeAsStringSync(testFileContent);

  print('\nGenerated: $outputFile (${testEntries.length} tests)');

  // Phase 4: Write manifest.
  final manifest = {
    'generated_at': DateTime.now().toIso8601String(),
    'input_dir': inputDir,
    'output_file': outputFile,
    'stats': {
      'total_files': report.total,
      'included_by_filter': included.length,
      'transformed': testEntries.length,
      'transform_failed': transformFailed,
      'excluded': report.excluded,
      'skipped': report.skipped,
      'not_test': report.notTest,
    },
    'exclude_reasons': report.reasonCounts,
  };

  final manifestFile = '$outputDir/manifest.json';
  File(manifestFile).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest));
  print('Manifest: $manifestFile');
}

void _printUsage() {
  print('Usage: fvm dart tool/co19_adapter/adapt.dart '
      '[--co19-root <path>] <co19-subdir>');
  print('');
  print('Options:');
  print('  --co19-root  Path to co19 root '
      '(default: ../../third_party/co19)');
  print('');
  print('Example:');
  print('  fvm dart tool/co19_adapter/adapt.dart Language/Expressions');
}
