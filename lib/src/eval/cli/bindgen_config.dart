import 'dart:io';
import 'package:yaml/yaml.dart';

/// bindgen.yaml 解析后的数据结构。
/// 配置文件 = @Bind 注解的展开态。
class BindgenConfig {
  final String? output;
  final List<LibraryConfig> libraries;

  BindgenConfig({this.output, required this.libraries});

  factory BindgenConfig.fromYaml(String yamlString) {
    final doc = loadYaml(yamlString) as YamlMap;
    final libs = doc['libraries'] as YamlList?;
    if (libs == null) {
      throw FormatException('bindgen.yaml 必须包含 libraries 字段');
    }
    return BindgenConfig(
      output: doc['output'] as String?,
      libraries: libs.map((e) => LibraryConfig.fromYaml(e)).toList(),
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

  LibraryConfig({
    required this.uri,
    this.output,
    this.classes = const [],
    this.enums = const [],
    this.functions = const [],
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
    );
  }
}

class ClassEntry {
  final String name;
  final bool bridge;
  final List<String> extern;

  ClassEntry({
    required this.name,
    this.bridge = false,
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
      extern: (map['extern'] as YamlList?)?.cast<String>().toList() ?? [],
    );
  }
}
