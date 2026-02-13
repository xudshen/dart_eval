import 'dart:io';

import 'package:change_case/change_case.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/bindgen/bindgen.dart';
import 'package:dart_eval/src/eval/cli/bindgen_config.dart';
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
  BindgenConfig? config,
}) async {
  if (verbose) print('Loading files...');

  final projectRoot = findProjectRoot(Directory(projectPath));
  final bindgen = Bindgen();

  // Read pubspec & package config
  final packageConfig = getPackageConfig(projectRoot);
  final pubspecFile = File(join(projectRoot.path, 'pubspec.yaml'));
  final pubspec = Pubspec.parse(pubspecFile.readAsStringSync());
  final packageName = pubspec.name;

  // Load bindings from explicit paths, project defaults, and dependencies
  final effectiveBindingPaths = [
    ...(bindingPaths.isNotEmpty
        ? bindingPaths
        : defaultBindingPaths(projectRoot.path)),
  ];
  // Auto-discover binding JSONs from resolved dependency packages
  for (final package in packageConfig.packages) {
    if (package.name == packageName) continue;
    try {
      final depPath = package.packageUriRoot.toFilePath();
      final depBindingsDir = join(depPath, '_eval', 'bindings');
      if (Directory(depBindingsDir).existsSync()) {
        effectiveBindingPaths.add(depBindingsDir);
      }
    } catch (_) {
      // packageUriRoot might not be a file URI (e.g. pub cache on Windows)
    }
  }
  loadBindingsInto(bindgen, effectiveBindingPaths, verbose: verbose);

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

  // ── Config mode ──────────────────────────────────────────────────
  if (config != null) {
    // Plugin output is at the top-level config output dir
    final pluginOutputDir = config.output ?? outputDir ?? 'lib/_eval';
    final pluginOutputPath = join(projectRoot.path, pluginOutputDir);

    for (final lib in config.libraries) {
      // When library has its own output, use it directly (it already
      // includes the desired subdirectory path like lib/_eval/src/widgets).
      // Otherwise, append src/ to the default output dir.
      final libOutputPath = lib.output != null
          ? join(projectRoot.path, lib.output!)
          : join(projectRoot.path, pluginOutputDir, 'src');
      Directory(libOutputPath).createSync(recursive: true);

      // Compute file prefix for plugin imports (relative from plugin dir)
      // e.g., "src" (default) or "src/widgets" (per-library)
      final relFromPlugin = relative(libOutputPath, from: pluginOutputPath);
      final filePrefix = relFromPlugin == '.' ? '' : relFromPlugin;

      for (final cls in lib.classes) {
        final output = await bindgen.parseFromConfig(
          libraryUri: lib.uri,
          className: cls.name,
          overrideLibrary: lib.uri,
          isBridge: cls.bridge,
          externMembers: cls.extern,
          filePrefix: filePrefix,
        );
        if (output != null) {
          _writeConfigOutput(
              output, cls.name, libOutputPath, formatter, lib.uri);
          boundFiles.add('${cls.name} (${lib.uri})');
          if (verbose) print('Bound ${cls.name} from ${lib.uri}');
        }
      }
      for (final enumName in lib.enums) {
        final output = await bindgen.parseFromConfig(
          libraryUri: lib.uri,
          className: enumName,
          overrideLibrary: lib.uri,
          filePrefix: filePrefix,
        );
        if (output != null) {
          _writeConfigOutput(
              output, enumName, libOutputPath, formatter, lib.uri);
          boundFiles.add('$enumName (${lib.uri})');
          if (verbose) print('Bound $enumName from ${lib.uri}');
        }
      }
      for (final fnName in lib.functions) {
        final output = await bindgen.parseFromConfig(
          libraryUri: lib.uri,
          className: fnName,
          overrideLibrary: lib.uri,
          filePrefix: filePrefix,
        );
        if (output != null) {
          _writeConfigOutput(
              output, fnName, libOutputPath, formatter, lib.uri);
          boundFiles.add('$fnName (${lib.uri})');
          if (verbose) print('Bound $fnName from ${lib.uri}');
        }
      }
    }

    final allRegistered = [
      ...bindgen.registerClasses,
      ...bindgen.registerEnums,
      ...bindgen.registerFunctions,
    ];

    String mappingLines = '';
    if (boundFiles.isNotEmpty) {
      final barrels = _generateBarrelFiles(
        allRegistered: allRegistered,
        packageName: packageName,
        outputBasePath: pluginOutputPath,
        outputDir: pluginOutputDir,
        formatter: formatter,
        verbose: verbose,
      );

      final sourcesStr = _generateDartSources(
        allRegistered: allRegistered,
        packageName: packageName,
        projectRootPath: projectRoot.path,
        pluginOutputPath: pluginOutputPath,
        config: config,
        verbose: verbose,
      );

      mappingLines = [barrels.mappingLines, sourcesStr]
          .where((s) => s.isNotEmpty)
          .join('\n    ');
    }

    String? pluginPath;
    if (generatePlugin && boundFiles.isNotEmpty) {
      pluginPath = _generatePluginFile(
        bindgen: bindgen,
        packageName: packageName,
        outputBasePath: pluginOutputPath,
        formatter: formatter,
        verbose: verbose,
        mappingLines: mappingLines,
      );
    }

    if (boundFiles.isEmpty && verbose) {
      print('No types were bound from config.');
    } else if (verbose) {
      print('Created bindings for ${boundFiles.length} types.');
    }

    return BindResult(
      boundFileCount: boundFiles.length,
      boundFiles: boundFiles,
      pluginPath: pluginPath,
    );
  }

  // ── @Bind annotation mode (existing) ────────────────────────────
  final analyzePath = join(projectRoot.path, 'analysis_options.yaml');
  final excludes = readAnalyzerExcludes(File(analyzePath));

  // Determine output base directory
  final effectiveOutputDir = outputDir ?? 'lib';
  final outputBasePath = join(projectRoot.path, effectiveOutputDir);

  // Whether output dir differs from source dir (e.g. lib/_eval/ vs lib/)
  final separateOutputDir = outputDir != null && outputDir != 'lib';

  // Pre-register barrel mappings for the current package so that
  // same-package type references resolve via exportedLibMappings
  // during bindgen (the actual barrel files are written after the bind loop).
  if (separateOutputDir) {
    final prefix = relative(effectiveOutputDir, from: 'lib');
    final libDir = Directory(join(projectRoot.path, 'lib'));
    if (libDir.existsSync()) {
      for (final entity in libDir.listSync()) {
        if (entity is Directory && !basename(entity.path).startsWith('_')) {
          final dirName = basename(entity.path);
          final srcDirUri = 'package:$packageName/$dirName';
          final barrelUri = 'package:${posix.joinAll([
                packageName,
                prefix,
                '$dirName.dart',
              ])}';
          bindgen.addExportedLibraryMapping(srcDirUri, barrelUri);
        }
      }
    }
  }

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
        final relFromLib = relative(file.path, from: join(projectRoot.path, 'lib'))
            .replaceAll('\\', '/');
        final dirName = posix.dirname(relFromLib);
        final filePrefix = (separateOutputDir && dirName != '.') ? dirName : '';
        final output = await bindgen.parse(file, filename, uri, all,
            separateOutputDir: separateOutputDir,
            filePrefix: filePrefix);
        if (output != null) {
          if (verbose) print('Bound ${file.path}');
          boundFiles.add(file.path);
          if (singleFile) {
            final ogImport = "import '$uri';\n";
            singleResult = ogImport + singleResult + output;
          } else {
            // Compute output path: if outputDir differs from source dir,
            // mirror the source structure under outputDir
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

  final allRegistered = [
    ...bindgen.registerClasses,
    ...bindgen.registerEnums,
    ...bindgen.registerFunctions,
  ];

  String mappingLines = '';
  if (separateOutputDir && boundFiles.isNotEmpty) {
    final barrels = _generateBarrelFiles(
      allRegistered: allRegistered,
      packageName: packageName,
      outputBasePath: outputBasePath,
      outputDir: effectiveOutputDir,
      formatter: formatter,
      verbose: verbose,
    );

    final sourcesStr = _generateDartSources(
      allRegistered: allRegistered,
      packageName: packageName,
      projectRootPath: projectRoot.path,
      pluginOutputPath: outputBasePath,
      config: null,
      verbose: verbose,
    );

    mappingLines = [barrels.mappingLines, sourcesStr]
        .where((s) => s.isNotEmpty)
        .join('\n    ');
  }

  String? pluginPath;
  if (generatePlugin) {
    pluginPath = _generatePluginFile(
      bindgen: bindgen,
      packageName: packageName,
      outputBasePath: outputBasePath,
      formatter: formatter,
      verbose: verbose,
      mappingLines: mappingLines,
      pluginFileName: separateOutputDir ? 'plugin.dart' : 'eval_plugin.dart',
    );
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

/// Write a config-mode generated binding file.
void _writeConfigOutput(
  String output,
  String typeName,
  String outputPath,
  DartFormatter formatter,
  String libraryUri,
) {
  final snakeName = typeName
      .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
      .toLowerCase();
  final filePath = join(outputPath, '$snakeName.eval.dart');
  final ogImport = "import '$libraryUri';\n";
  final result = formatter.format(defaultImports + ogImport + output,
      uri: Uri.parse(filePath));
  File(filePath).writeAsStringSync(result);
}

/// Generate barrel files and ExportedLibraryMapping lines.
///
/// Groups registered types by eval file directory, writes a barrel `.dart`
/// file for each directory, and computes the mapping lines for
/// `configureForCompile()`. Used by both config mode and @Bind mode.
({Map<String, String> mappings, String mappingLines}) _generateBarrelFiles({
  required List<({String file, String uri, String name})> allRegistered,
  required String packageName,
  required String outputBasePath,
  required String outputDir,
  required DartFormatter formatter,
  required bool verbose,
}) {
  final generatedMappings = <String, String>{};
  final prefix = relative(outputDir, from: 'lib');

  // Group by eval file directory and track source directory URIs.
  // This handles re-exported types (e.g. TextRange from dart:ui
  // listed under widgets).
  final dirToData =
      <String, ({Set<String> evalFiles, Set<String> srcDirUris})>{};
  for (final reg in allRegistered) {
    final evalDir = posix.dirname(reg.file); // e.g. "src/ui"
    final srcUri = Uri.parse(reg.uri);
    final srcDirUri = srcUri.path.contains('/')
        ? '${srcUri.scheme}:${posix.dirname(srcUri.path)}'
        : '${srcUri.scheme}:${srcUri.path}';
    final data = dirToData.putIfAbsent(
        evalDir, () => (evalFiles: <String>{}, srcDirUris: <String>{}));
    data.evalFiles.add(reg.file);
    data.srcDirUris.add(srcDirUri);
  }

  for (final entry in dirToData.entries) {
    final evalDir = entry.key;
    final evalFiles = entry.value.evalFiles;
    final srcDirUris = entry.value.srcDirUris;

    final barrelFileName = '$evalDir.dart';
    final barrelFilePath = join(outputBasePath, barrelFileName);

    final barrelUri = 'package:${posix.joinAll([
          packageName,
          prefix,
          barrelFileName,
        ])}';

    // Export paths relative to barrel file directory
    final barrelDir = posix.dirname(barrelFileName);
    final exports = evalFiles
        .map((f) => "export '${posix.relative(f, from: barrelDir)}';")
        .join('\n');
    Directory(dirname(barrelFilePath)).createSync(recursive: true);
    File(barrelFilePath).writeAsStringSync(
        formatter.format(exports, uri: Uri.parse(barrelUri)));

    for (final srcDirUri in srcDirUris) {
      // Only claim a mapping if this eval directory is the "native"
      // home for this source URI (directory names match), OR if no
      // native home has claimed it yet. This prevents cross-library
      // re-exports from stealing another group's mapping.
      final srcDirName = posix.basename(Uri.parse(srcDirUri).path);
      final evalDirName = posix.basename(evalDir);
      if (srcDirName == evalDirName) {
        // Native match — always overwrite
        generatedMappings[srcDirUri] = barrelUri;
      } else {
        // Cross-library re-export — only claim if unclaimed
        generatedMappings.putIfAbsent(srcDirUri, () => barrelUri);
      }
    }
  }

  if (verbose && generatedMappings.isNotEmpty) {
    print('Generated ${generatedMappings.length} barrel file(s) '
        'for exported library mappings.');
  }

  final mappingLines = generatedMappings.entries
      .map((e) =>
          "registry.addExportedLibraryMapping('${e.key}', '${e.value}');")
      .join('\n    ');

  return (mappings: generatedMappings, mappingLines: mappingLines);
}

/// Generate `addSource(DartSource(...))` lines for `configureForCompile()`.
///
/// In config mode ([config] != null), generates per-library DartSources
/// with proper exports and re-exports from config.
/// In @Bind mode ([config] == null), synthesizes a barrel DartSource from
/// registered types and registers it for the main package entry point
/// plus any feature export files (services.dart, widgets.dart, etc.).
String _generateDartSources({
  required List<({String file, String uri, String name})> allRegistered,
  required String packageName,
  required String projectRootPath,
  required String pluginOutputPath,
  BindgenConfig? config,
  required bool verbose,
}) {
  final sourceLines = <String>[];

  if (config != null) {
    // ── Config mode ──────────────────────────────────────────────
    // Build prefix→lib mapping to associate registered types with config libs
    final prefixToLib = <String, LibraryConfig>{};
    for (final lib in config.libraries) {
      final libOutPath = lib.output != null
          ? join(projectRootPath, lib.output!)
          : join(pluginOutputPath, 'src');
      final rel = relative(libOutPath, from: pluginOutputPath);
      prefixToLib[rel == '.' ? '' : rel] = lib;
    }

    // Group actualUri values by config library
    final libUriToSrcUris = <String, Set<String>>{};
    for (final reg in allRegistered) {
      for (final pfx in prefixToLib.keys) {
        final matches = pfx.isEmpty
            ? !reg.file.contains('/')
            : reg.file.startsWith('$pfx/');
        if (matches) {
          libUriToSrcUris
              .putIfAbsent(prefixToLib[pfx]!.uri, () => <String>{})
              .add(reg.uri);
          break;
        }
      }
    }

    // Generate a DartSource for each config library
    for (final lib in config.libraries) {
      final srcUris = libUriToSrcUris[lib.uri];
      if (srcUris == null || srcUris.isEmpty) continue;

      final libParsed = Uri.parse(lib.uri);
      final isDart = libParsed.scheme == 'dart';
      final libName = isDart
          ? 'dart.${libParsed.path}'
          : posix.basenameWithoutExtension(libParsed.path);
      final libDir =
          isDart ? libParsed.path : posix.dirname(libParsed.path);

      final buf = StringBuffer();
      buf.writeln('library $libName;');

      // Export statements for bound types' actual source files
      final exportPaths = <String>{};
      for (final srcUri in srcUris) {
        final srcParsed = Uri.parse(srcUri);
        if (isDart || srcParsed.scheme != libParsed.scheme) {
          // Skip: dart: lib types are at library URI itself, and
          // cross-scheme URIs (e.g. dart:ui type listed under
          // package:flutter/widgets) can't be relative-pathed
          continue;
        }
        final relPath = posix.relative(srcParsed.path, from: libDir);
        // Skip self-reference (e.g. material.dart exporting material.dart)
        if (relPath != posix.basename(libParsed.path)) {
          exportPaths.add(relPath);
        }
      }
      for (final p in exportPaths.toList()..sort()) {
        buf.writeln("export '$p';");
      }

      // Cross-library re-exports from config
      for (final reUri in lib.reexports) {
        final reParsed = Uri.parse(reUri);
        if (reParsed.scheme == libParsed.scheme) {
          final relPath = isDart
              ? reParsed.path
              : posix.relative(reParsed.path, from: libDir);
          buf.writeln("export '$relPath';");
        } else {
          buf.writeln("export '$reUri';");
        }
      }

      final content = buf.toString().trimRight();
      sourceLines.add(
          "registry.addSource(DartSource('${lib.uri}', '''$content'''));");
    }
  } else {
    // ── @Bind mode ───────────────────────────────────────────────
    // Synthesize DartSource from registered types
    final exports = <String>{};
    for (final reg in allRegistered) {
      final srcUri = Uri.parse(reg.uri);
      final relFromPkg =
          srcUri.path.substring(srcUri.path.indexOf('/') + 1);
      exports.add("export '$relFromPkg';");
    }

    if (exports.isNotEmpty) {
      final content = (exports.toList()..sort()).join('\n');
      sourceLines.add("registry.addSource(DartSource("
          "'package:$packageName/$packageName.dart', '''$content'''));");

      // Register feature export files (services.dart, widgets.dart, etc.)
      // so bundles can use documented import paths like
      // `import 'package:fab_service/services.dart'`.
      final libDir = Directory(join(projectRootPath, 'lib'));
      if (libDir.existsSync()) {
        final mainFile = '$packageName.dart';
        for (final entity in libDir.listSync()) {
          if (entity is File) {
            final name = basename(entity.path);
            if (name.endsWith('.dart') &&
                name != mainFile &&
                !name.startsWith('_')) {
              sourceLines.add("registry.addSource(DartSource("
                  "'package:$packageName/$name', '''$content'''));");
            }
          }
        }
      }
    }
  }

  if (verbose && sourceLines.isNotEmpty) {
    print('Generated ${sourceLines.length} DartSource(s).');
  }

  return sourceLines.join('\n    ');
}

/// Generate plugin.dart file from registered bindings.
String _generatePluginFile({
  required Bindgen bindgen,
  required String packageName,
  required String outputBasePath,
  required DartFormatter formatter,
  required bool verbose,
  required String mappingLines,
  String pluginFileName = 'plugin.dart',
}) {
  final pluginFilePath = join(outputBasePath, pluginFileName);
  Directory(dirname(pluginFilePath)).createSync(recursive: true);

  // Generate imports from registered eval files.
  // The file field already contains the relative path from the plugin dir
  // (e.g. "src/random.eval.dart" or "src/widgets/container.eval.dart").
  final importPaths = <String>{};
  for (final e in [
    ...bindgen.registerClasses,
    ...bindgen.registerEnums,
    ...bindgen.registerFunctions,
  ]) {
    importPaths.add(e.file);
  }

  final pluginContent = '''
import 'package:dart_eval/dart_eval_bridge.dart';
${importPaths.map((p) => "import '$p';").join('\n')}

/// [EvalPlugin] for $packageName
class ${packageName.toPascalCase()}Plugin implements EvalPlugin {
  const ${packageName.toPascalCase()}Plugin();

  @override
  String get identifier => 'package:${packageName.toLowerCase()}';

  @override
  void configureForCompile(BridgeDeclarationRegistry registry) {
    ${bindgen.registerClasses.map((e) => 'registry.defineBridgeClass(\$${e.name}.\$declaration);').join('\n')}
    ${bindgen.registerEnums.map((e) => 'registry.defineBridgeEnum(\$${e.name}.\$declaration);').join('\n')}
    ${bindgen.registerFunctions.map((e) => 'registry.defineBridgeTopLevelFunction(\$${e.name}Fn.\$declaration);').join('\n')}
    $mappingLines
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
      uri: Uri.parse('package:$packageName/$pluginFileName')));
  if (verbose) print('Generated plugin file: $pluginFilePath');
  return pluginFilePath;
}
