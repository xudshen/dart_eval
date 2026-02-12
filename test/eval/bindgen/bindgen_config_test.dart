import 'dart:io';

import 'package:dart_eval/src/eval/bindgen/bindgen.dart';
import 'package:dart_eval/src/eval/cli/utils.dart';
import 'package:test/test.dart';

/// 验证 Bindgen.parseFromConfig() 能为无 @Bind 注解的原始类生成绑定。
/// 使用 dart:math 的 Random 类作为目标。
void main() {
  group('Bindgen.parseFromConfig() — wrapper 模式', () {
    late Bindgen bindgen;

    setUpAll(() {
      bindgen = Bindgen();
      final projectRoot = findProjectRoot(Directory.current);
      final packageConfig = getPackageConfig(projectRoot);
      for (final package in packageConfig.packages) {
        bindgen.inject(package: package);
      }
    });

    test('为 Random 类生成绑定', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Random',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNotNull, reason: '应为 Random 生成绑定代码');
      expect(output, contains('\$Random'), reason: '应生成 \$Random 类');
    });

    test('生成 configureForRuntime', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Random',
        overrideLibrary: 'dart:math',
      );

      expect(output, contains('configureForRuntime'),
          reason: '应生成 configureForRuntime 方法');
    });

    test('生成 \$declaration', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Random',
        overrideLibrary: 'dart:math',
      );

      expect(output, contains('\$declaration'),
          reason: '应生成 \$declaration 常量');
      expect(output, contains("'dart:math'"),
          reason: 'overrideLibrary 应设为 dart:math');
    });

    test('nextInt 方法已绑定', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Random',
        overrideLibrary: 'dart:math',
      );

      expect(output, contains("'nextInt'"),
          reason: 'nextInt 方法应出现在绑定中');
    });

    test('nextDouble 方法已绑定', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Random',
        overrideLibrary: 'dart:math',
      );

      expect(output, contains("'nextDouble'"),
          reason: 'nextDouble 方法应出现在绑定中');
    });

    test('注册到 registerClasses', () async {
      final bindgenLocal = Bindgen();
      final projectRoot = findProjectRoot(Directory.current);
      final packageConfig = getPackageConfig(projectRoot);
      for (final package in packageConfig.packages) {
        bindgenLocal.inject(package: package);
      }

      await bindgenLocal.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Random',
        overrideLibrary: 'dart:math',
      );

      expect(bindgenLocal.registerClasses, hasLength(1));
      expect(bindgenLocal.registerClasses.first.name, 'Random');
      expect(bindgenLocal.registerClasses.first.uri, 'dart:math');
    });
  });
}
