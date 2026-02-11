import 'dart:io';

import 'package:change_case/change_case.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/bindgen/bindgen.dart';
import 'package:dart_eval/src/eval/cli/bindings.dart';
import 'package:dart_eval/src/eval/cli/utils.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart' show loadYaml, YamlList;

const defaultImports = '''
// ignore_for_file: unused_import, unnecessary_import
// ignore_for_file: always_specify_types, avoid_redundant_argument_values
// ignore_for_file: sort_constructors_first
// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
''';

/// Result of a programmatic bind operation.
class BindResult {
  final int boundFileCount;
  final List<String> boundFiles;
  final String? pluginPath;

  BindResult({
    required this.boundFileCount,
    required this.boundFiles,
    this.pluginPath,
  });
}

/// Generate dart_eval bindings for a project programmatically.
///
/// - [projectPath]: root directory of the project (must contain pubspec.yaml)
/// - [outputDir]: output directory for generated files, relative to project
///   root (default: `lib/`, FAB uses `lib/_eval/`)
/// - [all]: bind all classes (not just @Bind-annotated ones)
/// - [singleFile]: generate a single output file instead of per-source files
/// - [generatePlugin]: generate an EvalPlugin class
/// - [bindingPaths]: additional directories containing binding JSON files;
///   if empty, auto-discovers from `<projectPath>/.dart_eval/bindings/`
/// - [verbose]: whether to print progress info
Future<BindResult> bind({
  required String projectPath,
  String? outputDir,
  bool all = false,
  bool singleFile = false,
  bool generatePlugin = true,
  List<String> bindingPaths = const [],
  bool verbose = false,
}) async {
  if (verbose) print('Loading files...');

  final projectRoot = findProjectRoot(Directory(projectPath));
  final bindgen = Bindgen();

  // Load bindings
  final effectiveBindingPaths = bindingPaths.isNotEmpty
      ? bindingPaths
      : defaultBindingPaths(projectRoot.path);
  loadBindingsInto(bindgen, effectiveBindingPaths, verbose: verbose);

  // Read pubspec
  final packageConfig = getPackageConfig(projectRoot);
  final pubspecFile = File(join(projectRoot.path, 'pubspec.yaml'));
  final pubspec = Pubspec.parse(pubspecFile.readAsStringSync());
  final packageName = pubspec.name;

  final version = Version.parse(Platform.version.split(' ').first);
  final formatter = DartFormatter(languageVersion: version);

  for (final package in packageConfig.packages) {
    if (package.name == packageName) {
      bindgen.inject(package: package);
      break;
    }
  }

  var singleResult = '';
  final boundFiles = <String>[];

  final analyzePath = join(projectRoot.path, 'analysis_options.yaml');
  final excludes = readAnalyzerExcludes(File(analyzePath));

  // Determine output base directory
  final effectiveOutputDir = outputDir ?? 'lib';
  final outputBasePath = join(projectRoot.path, effectiveOutputDir);

  // Prefix for cross-package eval imports (e.g. '_eval' for lib/_eval/)
  final evalOutputPrefix = outputDir != null && outputDir != 'lib'
      ? relative(outputDir, from: 'lib')
      : '';

  Future<void> bindLoop(String pkg, Directory dir, String root) async {
    if (!dir.existsSync()) return;
    for (final file in dir.listSync()) {
      final filename = basename(file.path);
      if (file is File &&
          filename.endsWith('.dart') &&
          !filename.endsWith('.eval.dart')) {
        final p = relative(file.path, from: root).replaceAll('\\', '/');
        if (excludes.any((e) => e.matches(p))) continue;
        final uri = 'package:${posix.join(packageName, p)}';
        final output = await bindgen.parse(file, filename, uri, all,
            evalOutputPrefix: evalOutputPrefix);
        if (output != null) {
          if (verbose) print('Bound ${file.path}');
          boundFiles.add(file.path);
          if (singleFile) {
            final ogImport = "import '$uri';\n";
            singleResult = ogImport + singleResult + output;
          } else {
            // Compute output path: if outputDir differs from source dir,
            // mirror the source structure under outputDir
            final relFromLib =
                relative(file.path, from: join(projectRoot.path, 'lib'));
            String outputFilePath;
            if (outputDir != null && outputDir != 'lib') {
              outputFilePath = join(
                outputBasePath,
                relFromLib.replaceAll('.dart', '.eval.dart'),
              );
              // Ensure directory exists
              Directory(dirname(outputFilePath)).createSync(recursive: true);
            } else {
              // Original behavior: output next to source file
              final outputFilename =
                  filename.replaceAll('.dart', '.eval.dart');
              outputFilePath = join(dir.path, outputFilename);
            }

            final ogImport = outputDir != null && outputDir != 'lib'
                ? "import '$uri';\n"
                : "import '$filename';\n";
            final result = formatter.format(defaultImports + ogImport + output,
                uri: Uri.parse(uri));
            File(outputFilePath).writeAsStringSync(result);
          }
        }
      } else if (file is Directory) {
        await bindLoop(pkg, file, root);
      }
    }
  }

  await bindLoop(packageName, Directory(join(projectRoot.path, 'lib')),
      join(projectRoot.path, 'lib'));

  if (singleFile) {
    final outPath =
        join(outputBasePath, 'dart_eval_bindings.dart');
    Directory(dirname(outPath)).createSync(recursive: true);
    final result = formatter.format(defaultImports + singleResult,
        uri: Uri.parse('package:$packageName/dart_eval_bindings.dart'));
    File(outPath).writeAsStringSync(result);
  }

  String? pluginPath;
  if (generatePlugin) {
    final pluginFilePath = join(outputBasePath, outputDir != null && outputDir != 'lib'
        ? 'plugin.dart'
        : 'eval_plugin.dart');
    Directory(dirname(pluginFilePath)).createSync(recursive: true);

    final pluginContent = '''
import 'package:dart_eval/dart_eval_bridge.dart';
${[
      ...bindgen.registerClasses,
      ...bindgen.registerEnums
    ].map((e) => e.uri.substring(e.uri.indexOf('/') + 1)).toSet().map((e) => 'import \'${e.replaceAll('.dart', '.eval.dart')}\';').join('\n')}

/// [EvalPlugin] for $packageName
class ${packageName.toPascalCase()}Plugin implements EvalPlugin {
  @override
  String get identifier => 'package:${packageName.toLowerCase()}';

  @override
  void configureForCompile(BridgeDeclarationRegistry registry) {
    ${bindgen.registerClasses.map((e) => 'registry.defineBridgeClass(\$${e.name}.\$declaration);').join('\n')}
    ${bindgen.registerEnums.map((e) => 'registry.defineBridgeEnum(\$${e.name}.\$declaration);').join('\n')}
    ${bindgen.registerFunctions.map((e) => 'registry.defineBridgeTopLevelFunction(\$${e.name}Fn.\$declaration);').join('\n')}
  }

  @override
  void configureForRuntime(Runtime runtime) {
    ${bindgen.registerClasses.map((e) => '\$${e.name}.configureForRuntime(runtime);').join('\n')}
    ${bindgen.registerEnums.map((e) => '\$${e.name}.configureForRuntime(runtime);').join('\n')}
    ${bindgen.registerFunctions.map((e) => '\$${e.name}Fn.configureForRuntime(runtime);').join('\n')}
  }
}
''';
    File(pluginFilePath).writeAsStringSync(formatter.format(pluginContent,
        uri: Uri.parse('package:$packageName/eval_plugin.dart')));
    if (verbose) print('Generated plugin file: $pluginFilePath');
    pluginPath = pluginFilePath;
  } else {
    if (verbose) print('Skipping plugin generation.');
  }

  if (boundFiles.isEmpty) {
    if (verbose) {
      print('No files were bound. You may need to add the @Bind annotation '
          'from the eval_annotation package, or pass the --all flag to '
          'bind all classes.');
    }
  } else {
    if (verbose) print('Created bindings for ${boundFiles.length} files.');
  }

  return BindResult(
    boundFileCount: boundFiles.length,
    boundFiles: boundFiles,
    pluginPath: pluginPath,
  );
}

/// CLI entry point for `dart_eval bind`. Delegates to [bind].
void cliBind(
    {bool singleFile = false,
    bool all = false,
    bool generatePlugin = true}) async {
  await bind(
    projectPath: current,
    all: all,
    singleFile: singleFile,
    generatePlugin: generatePlugin,
    verbose: true,
  );
}

List<Glob> readAnalyzerExcludes(File path) {
  if (!path.existsSync()) return [];
  final doc = loadYaml(path.readAsStringSync());
  final excludes = (doc['analyzer'] ?? <String, dynamic>{})['exclude'];
  if (excludes == null || excludes is! YamlList) return [];
  final reLib = RegExp(r'^lib/');
  return excludes
      .whereType<String>()
      .where((value) => value.startsWith('lib/'))
      .map((value) => Glob(value.replaceFirst(reLib, '')))
      .toList();
}
