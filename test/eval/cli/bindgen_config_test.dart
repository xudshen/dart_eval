import 'package:test/test.dart';
import 'package:dart_eval/src/eval/cli/bindgen_config.dart';

void main() {
  group('BindgenConfig', () {
    test('解析按 library 分组的配置', () {
      final yaml = '''
libraries:
  - uri: dart:math
    classes:
      - Random
      - Point
    functions:
      - min
      - max
''';
      final config = BindgenConfig.fromYaml(yaml);
      expect(config.output, isNull);
      expect(config.libraries, hasLength(1));
      expect(config.libraries.first.uri, 'dart:math');
      expect(config.libraries.first.output, isNull);
      expect(config.libraries.first.classes, hasLength(2));
      expect(config.libraries.first.classes[0].name, 'Random');
      expect(config.libraries.first.classes[1].name, 'Point');
      expect(config.libraries.first.functions, ['min', 'max']);
    });

    test('解析顶层和 library 级别的 output', () {
      final yaml = '''
output: lib/_eval
libraries:
  - uri: dart:math
    classes:
      - Random
  - uri: package:dio/dio.dart
    output: ../fab_dio/lib/_eval
    classes:
      - Dio
''';
      final config = BindgenConfig.fromYaml(yaml);
      expect(config.output, 'lib/_eval');
      expect(config.libraries[0].output, isNull);
      expect(config.libraries[1].output, '../fab_dio/lib/_eval');
    });

    test('类条目支持简写和展开两种格式', () {
      final yaml = '''
libraries:
  - uri: package:flutter/widgets.dart
    classes:
      - Container
      - name: StatelessWidget
        bridge: true
      - name: SomeClass
        extern:
          - internalGetter
''';
      final config = BindgenConfig.fromYaml(yaml);
      final classes = config.libraries.first.classes;
      expect(classes[0].name, 'Container');
      expect(classes[0].bridge, isFalse);
      expect(classes[0].extern, isEmpty);

      expect(classes[1].name, 'StatelessWidget');
      expect(classes[1].bridge, isTrue);

      expect(classes[2].name, 'SomeClass');
      expect(classes[2].extern, ['internalGetter']);
    });

    test('多个 library 分组', () {
      final yaml = '''
libraries:
  - uri: package:flutter/material.dart
    classes:
      - Card
    enums:
      - MaterialType
  - uri: package:flutter/widgets.dart
    classes:
      - Container
''';
      final config = BindgenConfig.fromYaml(yaml);
      expect(config.libraries, hasLength(2));
      expect(config.libraries[0].enums, ['MaterialType']);
      expect(config.libraries[1].classes.first.name, 'Container');
    });

    test('缺少 libraries 时抛异常', () {
      expect(
        () => BindgenConfig.fromYaml('foo: bar'),
        throwsA(isA<FormatException>()),
      );
    });

    group('resolve_dependencies config', () {
      test('parses resolve_dependencies and resolve_depth', () {
        final config = BindgenConfig.fromYaml('''
output: lib/_eval
resolve_dependencies: true
resolve_depth: 3
resolve_exclude:
  - InteractiveInkFeatureFactory
libraries:
  - uri: dart:math
    classes: [Random]
''');
        expect(config.resolveDependencies, isTrue);
        expect(config.resolveDepth, 3);
        expect(config.resolveExclude, contains('InteractiveInkFeatureFactory'));
      });

      test('resolve defaults to false with depth 2', () {
        final config = BindgenConfig.fromYaml('''
libraries:
  - uri: dart:math
    classes: [Random]
''');
        expect(config.resolveDependencies, isFalse);
        expect(config.resolveDepth, 2);
        expect(config.resolveExclude, isEmpty);
      });
    });
  });
}
