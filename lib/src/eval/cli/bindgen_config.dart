import 'dart:io';
import 'package:yaml/yaml.dart';

/// bindgen.yaml 解析后的数据结构。
/// 配置文件 = @Bind 注解的展开态。
class BindgenConfig {
  final String? output;
  final List<LibraryConfig> libraries;
  final bool resolveDependencies;
  final int resolveDepth;
  final List<String> resolveExclude;
  final List<EvalSourceEntry> evalSources;

  BindgenConfig({
    this.output,
    required this.libraries,
    this.resolveDependencies = false,
    this.resolveDepth = 2,
    this.resolveExclude = const [],
    this.evalSources = const [],
  });

  factory BindgenConfig.fromYaml(String yamlString) {
    final doc = loadYaml(yamlString) as YamlMap;
    final libs = doc['libraries'] as YamlList?;
    if (libs == null) {
      throw FormatException('bindgen.yaml 必须包含 libraries 字段');
    }
    return BindgenConfig(
      output: doc['output'] as String?,
      libraries: libs.map((e) => LibraryConfig.fromYaml(e)).toList(),
      resolveDependencies: doc['resolve_dependencies'] as bool? ?? false,
      resolveDepth: doc['resolve_depth'] as int? ?? 2,
      resolveExclude: (doc['resolve_exclude'] as YamlList?)
              ?.cast<String>()
              .toList() ??
          [],
      evalSources: (doc['eval_sources'] as YamlList?)
              ?.map((e) => EvalSourceEntry.fromYaml(e))
              .toList() ??
          [],
    );
  }

  factory BindgenConfig.fromFile(String path) {
    return BindgenConfig.fromYaml(File(path).readAsStringSync());
  }
}

class LibraryConfig {
  final String uri;
  final String? output;
  final List<ClassEntry> classes;
  final List<String> enums;
  final List<String> functions;

  /// Other library URIs that this library re-exports.
  /// E.g., `package:flutter/material.dart` re-exports `package:flutter/widgets.dart`.
  final List<String> reexports;

  LibraryConfig({
    required this.uri,
    this.output,
    this.classes = const [],
    this.enums = const [],
    this.functions = const [],
    this.reexports = const [],
  });

  factory LibraryConfig.fromYaml(dynamic value) {
    final map = value as YamlMap;
    return LibraryConfig(
      uri: map['uri'] as String,
      output: map['output'] as String?,
      classes: (map['classes'] as YamlList?)
              ?.map((e) => ClassEntry.fromYaml(e))
              .toList() ??
          [],
      enums: (map['enums'] as YamlList?)?.cast<String>().toList() ?? [],
      functions:
          (map['functions'] as YamlList?)?.cast<String>().toList() ?? [],
      reexports:
          (map['reexports'] as YamlList?)?.cast<String>().toList() ?? [],
    );
  }
}

class ClassEntry {
  final String name;
  final bool bridge;

  /// When true and [bridge] is also true, generate a companion wrapper class
  /// alongside the bridge class (so native instances can be wrapped for eval).
  final bool wrap;
  final List<String> extern;

  ClassEntry({
    required this.name,
    this.bridge = false,
    this.wrap = false,
    this.extern = const [],
  });

  factory ClassEntry.fromYaml(dynamic value) {
    if (value is String) {
      return ClassEntry(name: value);
    }
    final map = value as YamlMap;
    return ClassEntry(
      name: map['name'] as String,
      bridge: map['bridge'] as bool? ?? false,
      wrap: map['wrap'] as bool? ?? false,
      extern: (map['extern'] as YamlList?)?.cast<String>().toList() ?? [],
    );
  }
}

/// An eval source entry: a const Dart source string injected into the compiler
/// as-is (not bridge/wrapper). Used for types like Icons with 1500+ static
/// const fields where bridge binding is impractical.
class EvalSourceEntry {
  /// URI registered in the compiler, e.g. `package:flutter/src/material/icons.dart`
  final String uri;

  /// Import path relative to project root, e.g. `lib/src/material/icons_source.dart`
  final String importPath;

  /// Const variable name holding the source string, e.g. `materialIconsSource`
  final String constName;

  /// Library URI whose DartSource barrel should re-export this source (optional).
  /// E.g. `package:flutter/material.dart`
  final String? exportFrom;

  EvalSourceEntry({
    required this.uri,
    required this.importPath,
    required this.constName,
    this.exportFrom,
  });

  factory EvalSourceEntry.fromYaml(dynamic value) {
    final map = value as YamlMap;
    return EvalSourceEntry(
      uri: map['uri'] as String,
      importPath: map['import'] as String,
      constName: map['const'] as String,
      exportFrom: map['export_from'] as String?,
    );
  }
}
