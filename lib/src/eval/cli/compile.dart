import 'dart:io';
import 'dart:typed_data';

import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/cli/bindings.dart';
import 'package:dart_eval/src/eval/cli/utils.dart';
import 'package:path/path.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

/// Result of a programmatic compilation.
class CompileResult {
  final Uint8List bytecode;
  final int sourceLength;
  final Duration elapsed;

  CompileResult({
    required this.bytecode,
    required this.sourceLength,
    required this.elapsed,
  });
}

/// Compile a dart_eval project programmatically.
///
/// - [projectPath]: root directory of the project (must contain pubspec.yaml)
/// - [outputPath]: path to write the compiled .evc file
/// - [bindingPaths]: additional directories containing binding JSON files;
///   if empty, auto-discovers from `<projectPath>/.dart_eval/bindings/`
/// - [diagnosticMode]: how to handle diagnostics (default: throw + print all)
/// - [verbose]: whether to print progress info
CompileResult compile({
  required String projectPath,
  required String outputPath,
  List<String> bindingPaths = const [],
  DiagnosticMode diagnosticMode = DiagnosticMode.throwErrorPrintAll,
  bool verbose = false,
}) {
  final compiler = Compiler()..diagnosticMode = diagnosticMode;

  if (verbose) print('Loading files...');

  final projectRoot = findProjectRoot(Directory(projectPath));

  // Load bindings
  final effectiveBindingPaths = bindingPaths.isNotEmpty
      ? bindingPaths
      : defaultBindingPaths(projectRoot.path);
  loadBindingsInto(compiler, effectiveBindingPaths, verbose: verbose);

  final bridgedPackages = <String>[];
  for (final lib in compiler.bridgedLibraries) {
    if (lib.startsWith('package:')) {
      final packageName = lib.split('/')[0].substring(8);
      if (!bridgedPackages.contains(packageName)) {
        bridgedPackages.add(packageName);
      }
    }
  }

  // Read pubspec
  final pubspecFile = File(join(projectRoot.path, 'pubspec.yaml'));
  final pubspec = Pubspec.parse(pubspecFile.readAsStringSync());
  final packageName = pubspec.name;
  compiler.version = pubspec.version?.canonicalizedVersion;

  // Collect source files
  final data = <String, Map<String, String>>{};
  var sourceLength = 0;

  void addFiles(String pkg, Directory dir, String root) {
    if (!dir.existsSync()) return;
    if (!data.containsKey(pkg)) {
      data[pkg] = {};
    }
    for (final file in dir.listSync()) {
      if (file is File && file.path.endsWith('.dart')) {
        final fileData = file.readAsStringSync();
        sourceLength += fileData.length;
        final p = relative(file.path, from: root).replaceAll('\\', '/');
        data[pkg]![p] = fileData;
      } else if (file is Directory) {
        addFiles(pkg, file, root);
      }
    }
  }

  addFiles(packageName, Directory(join(projectRoot.path, 'lib')),
      join(projectRoot.path, 'lib'));
  addFiles(packageName, Directory(join(projectRoot.path, 'bin')),
      join(projectRoot.path, 'bin'));

  // Add package dependencies
  final packageConfig = getPackageConfig(projectRoot);
  if (verbose && packageConfig.packages.length > 1) {
    print('Adding packages from package config:');
  }

  for (final package in packageConfig.packages) {
    if (bridgedPackages.contains(package.name) ||
        packageName == package.name) {
      continue;
    }
    if (verbose) stdout.write('${package.name} ');

    String filepath;
    try {
      filepath = package.packageUriRoot.toFilePath();
    } catch (e) {
      filepath = package.packageUriRoot.toString();
    }
    addFiles(package.name, Directory(filepath), filepath);
  }
  if (verbose) stdout.write('\n');

  // Compile
  if (verbose) print('Compiling package $packageName...');
  final ts = DateTime.now().millisecondsSinceEpoch;
  final programSource = compiler.compile(data);
  final out = programSource.write();
  final elapsed =
      Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - ts);

  // Write output
  File(outputPath).writeAsBytesSync(out);

  if (verbose) {
    print('Compiled $sourceLength characters Dart to ${out.length} bytes '
        'EVC in ${elapsed.inMilliseconds} ms: $outputPath');
  }

  return CompileResult(
    bytecode: out,
    sourceLength: sourceLength,
    elapsed: elapsed,
  );
}

/// CLI entry point for `dart_eval compile`. Delegates to [compile].
void cliCompile(String outputName) {
  compile(
    projectPath: current,
    outputPath: outputName,
    verbose: true,
  );
}
