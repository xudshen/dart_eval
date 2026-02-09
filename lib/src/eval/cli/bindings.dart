import 'dart:convert';
import 'dart:io';

import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/bindgen/bindgen.dart';
import 'package:path/path.dart';

/// Load binding JSON files from [bindingPaths] into a
/// [BridgeDeclarationRegistry] (e.g. a [Compiler] or [Bindgen]).
///
/// Each path should be a directory containing `*.json` binding files.
/// Non-existent paths are silently skipped.
void loadBindingsInto(
  BridgeDeclarationRegistry registry,
  List<String> bindingPaths, {
  bool verbose = false,
}) {
  for (final dirPath in bindingPaths) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));

    for (final file in files) {
      if (verbose) print('Found binding file: ${file.path}');
      final data = file.readAsStringSync();
      final decoded = (json.decode(data) as Map).cast<String, dynamic>();

      for (final cls in (decoded['classes'] as List).cast<Map>()) {
        registry.defineBridgeClass(BridgeClassDef.fromJson(cls.cast()));
      }
      for (final enm in (decoded['enums'] as List).cast<Map>()) {
        registry.defineBridgeEnum(BridgeEnumDef.fromJson(enm.cast()));
      }
      if (decoded.containsKey('sources')) {
        for (final src in (decoded['sources'] as List).cast<Map>()) {
          registry.addSource(DartSource(src['uri'], src['source']));
        }
      }
      if (decoded.containsKey('functions')) {
        for (final fn in (decoded['functions'] as List).cast<Map>()) {
          registry.defineBridgeTopLevelFunction(
              BridgeFunctionDeclaration.fromJson(fn.cast()));
        }
      }
      if (decoded.containsKey('exportedLibMappings') &&
          registry is Bindgen) {
        (decoded['exportedLibMappings'] as Map)
            .cast<String, String>()
            .forEach((key, value) {
          registry.addExportedLibraryMapping(key, value);
        });
      }
    }
  }
}

/// Discover default binding paths for a project.
///
/// Looks for `.dart_eval/bindings/` relative to [projectPath].
List<String> defaultBindingPaths(String projectPath) {
  final bindingsDir = join(projectPath, '.dart_eval', 'bindings');
  if (FileSystemEntity.typeSync(bindingsDir) ==
      FileSystemEntityType.directory) {
    return [bindingsDir];
  }
  return [];
}
