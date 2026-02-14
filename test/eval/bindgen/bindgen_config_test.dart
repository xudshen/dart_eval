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

  group('Bindgen.parseFromConfig() — 泛型生成', () {
    late Bindgen bindgen;

    setUpAll(() {
      bindgen = Bindgen();
      final projectRoot = findProjectRoot(Directory.current);
      final packageConfig = getPackageConfig(projectRoot);
      for (final package in packageConfig.packages) {
        bindgen.inject(package: package);
      }
    });

    test('泛型函数 min<T> 生成绑定', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'min',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNotNull, reason: '泛型函数应生成绑定');
      expect(output, contains('\$minFn'));
    });

    test('泛型函数 \$declaration 包含 generics map', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'min',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNotNull);
      expect(output, contains('generics:'),
          reason: '泛型函数的 BridgeFunctionDef 应包含 generics map');
      expect(output, contains('BridgeGenericParam'),
          reason: '泛型参数应使用 BridgeGenericParam 声明');
      expect(output, contains("'T'"),
          reason: '类型参数 T 应出现在 generics map 中');
    });

    test('泛型函数 max<T> 生成绑定', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'max',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNotNull, reason: '泛型函数应生成绑定');
      expect(output, contains('\$maxFn'));
    });

    test('泛型类 Point<T> 生成绑定', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Point',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNotNull, reason: '泛型类应生成绑定');
      expect(output, contains('\$Point'));
    });

    test('泛型类型注册到 registerClasses/registerFunctions', () async {
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

      expect(bindgenLocal.registerFunctions, hasLength(1),
          reason: '泛型函数应注册');
      expect(bindgenLocal.registerClasses, hasLength(1),
          reason: '泛型类应注册');
    });

    test('wrap-only 泛型类使用类型擦除（class header 无 <T>）', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Point',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNotNull);
      // Type erasure: class header should NOT contain <T>
      expect(output, contains('class \$Point implements \$Instance'));
      // But should NOT have <T> in the class header
      expect(output, isNot(contains('class \$Point<')));
    });

    test('泛型类 \$declaration 包含 generics map', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Point',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNotNull);
      expect(output, contains('generics:'));
      expect(output, contains('BridgeGenericParam'));
      expect(output, contains("'T'"));
    });

    test('泛型类成员使用 BridgeTypeRef.ref 引用类型参数', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Point',
        overrideLibrary: 'dart:math',
      );

      expect(output, isNotNull);
      // Type parameters in bridge metadata should use BridgeTypeRef.ref
      expect(output, contains('BridgeTypeRef.ref('));
    });

    test('bridge 模式泛型类 header 包含类型参数', () async {
      final output = await bindgen.parseFromConfig(
        libraryUri: 'dart:math',
        className: 'Point',
        overrideLibrary: 'dart:math',
        isBridge: true,
      );

      expect(output, isNotNull);
      // Bridge classes need type params for Dart compiler
      expect(output, contains('\$Point\$bridge<'));
      expect(output, contains('extends Point<'));
      expect(output, contains('\$Bridge<Point<'));
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
