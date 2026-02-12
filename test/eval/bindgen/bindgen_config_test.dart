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

  group('Bindgen.parseFromConfig() — bridge 模式', () {
    late Bindgen bindgen;

    setUpAll(() {
      bindgen = Bindgen();
      final projectRoot = findProjectRoot(Directory.current);
      final packageConfig = getPackageConfig(projectRoot);
      for (final package in packageConfig.packages) {
        bindgen.inject(package: package);
      }
    });

    test('bridge 模式生成 \$bridge 类', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Random',
        overrideLibrary: 'dart:math',
        isBridge: true,
      );

      expect(output, isNotNull);
      expect(output, contains('\$Random\$bridge'),
          reason: 'bridge 模式应生成 \$Random\$bridge 类');
      expect(output, contains('\$Bridge<Random>'),
          reason: 'bridge 类应 mixin \$Bridge<Random>');
    });

    test('bridge 模式注册名含 \$bridge 后缀', () async {
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
        isBridge: true,
      );

      expect(bindgenLocal.registerClasses.first.name, 'Random\$bridge');
    });
  });

  group('Bindgen.parseFromConfig() — 泛型跳过', () {
    late Bindgen bindgen;

    setUpAll(() {
      bindgen = Bindgen();
      final projectRoot = findProjectRoot(Directory.current);
      final packageConfig = getPackageConfig(projectRoot);
      for (final package in packageConfig.packages) {
        bindgen.inject(package: package);
      }
    });

    test('泛型函数 min<T> 返回 null（跳过）', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'min',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNull, reason: '泛型函数应被跳过');
    });

    test('泛型函数 max<T> 返回 null（跳过）', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'max',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNull, reason: '泛型函数应被跳过');
    });

    test('泛型类 Point<T> 返回 null（跳过）', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Point',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNull, reason: '泛型类应被跳过');
    });

    test('泛型类型不注册到 registerClasses/registerFunctions', () async {
      final bindgenLocal = Bindgen();
      final projectRoot = findProjectRoot(Directory.current);
      final packageConfig = getPackageConfig(projectRoot);
      for (final package in packageConfig.packages) {
        bindgenLocal.inject(package: package);
      }

      await bindgenLocal.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'min',
        overrideLibrary: 'dart:math',
      );
      await bindgenLocal.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Point',
        overrideLibrary: 'dart:math',
      );

      expect(bindgenLocal.registerFunctions, isEmpty,
          reason: '泛型函数不应注册');
      expect(bindgenLocal.registerClasses, isEmpty,
          reason: '泛型类不应注册');
    });
  });

  group('Bindgen.parseFromConfig() — 边界情况', () {
    late Bindgen bindgen;

    setUpAll(() {
      bindgen = Bindgen();
      final projectRoot = findProjectRoot(Directory.current);
      final packageConfig = getPackageConfig(projectRoot);
      for (final package in packageConfig.packages) {
        bindgen.inject(package: package);
      }
    });

    test('不存在的类返回 null', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'NonExistentClass',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNull);
    });

    test('生成文件名为 snake_case', () async {
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

      expect(bindgenLocal.registerClasses.first.file, 'random.eval.dart');
    });
  });
}
