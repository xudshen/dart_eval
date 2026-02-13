import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:collection/collection.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/bindgen/bridge.dart';
import 'package:dart_eval/src/eval/bindgen/bridge_declaration.dart';
import 'package:dart_eval/src/eval/bindgen/configure.dart';
import 'package:dart_eval/src/eval/bindgen/context.dart';
import 'package:dart_eval/src/eval/bindgen/enum.dart';
import 'package:dart_eval/src/eval/bindgen/function.dart';
import 'package:dart_eval/src/eval/bindgen/methods.dart';
import 'package:dart_eval/src/eval/bindgen/properties.dart';
import 'package:dart_eval/src/eval/bindgen/statics.dart';
import 'package:dart_eval/src/eval/bindgen/type.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'dart:io' as io;

import 'package:package_config/package_config.dart';
import 'package:path/path.dart';

/// Adapted from code by Alex Wallen (@a-wallen)
class Bindgen implements BridgeDeclarationRegistry {
  static final resourceProvider = PhysicalResourceProvider.INSTANCE;
  final includedPaths = [resourceProvider.pathContext.current];

  final _bridgeDeclarations = <String, List<BridgeDeclaration>>{};
  final _exportedLibMappings = <String, String>{};
  final List<({String file, String uri, String name})> registerClasses = [];
  final List<({String file, String uri, String name})> registerEnums = [];
  final List<({String file, String uri, String name})> registerFunctions = [];

  AnalysisContextCollection? _contextCollection;

  void inject({required Package package}) {
    String filepath;
    try {
      filepath = package.packageUriRoot.toFilePath();
    } catch (e) {
      filepath = package.packageUriRoot.toString();
    }
    includedPaths.add(normalize(filepath));
  }

  // Manually define a (unresolved) bridge class
  @override
  void defineBridgeClass(BridgeClassDef classDef) {
    if (!classDef.bridge && !classDef.wrap) {
      throw CompileError(
          'Cannot define a bridge class that\'s not either bridge or wrap');
    }
    final type = classDef.type;
    final spec = type.type.spec;

    if (spec == null) {
      throw CompileError(
          'Cannot define a bridge class that\'s already resolved, a ref, or a generic function type');
    }

    final libraryDeclarations = _bridgeDeclarations[spec.library];
    if (libraryDeclarations == null) {
      _bridgeDeclarations[spec.library] = [classDef];
    } else {
      libraryDeclarations.add(classDef);
    }
  }

  /// Define a bridged enum definition to be used when binding.
  @override
  void defineBridgeEnum(BridgeEnumDef enumDef) {
    final spec = enumDef.type.spec;
    if (spec == null) {
      throw CompileError(
          'Cannot define a bridge enum that\'s already resolved, a ref, or a generic function type');
    }

    final libraryDeclarations = _bridgeDeclarations[spec.library];
    if (libraryDeclarations == null) {
      _bridgeDeclarations[spec.library] = [enumDef];
    } else {
      libraryDeclarations.add(enumDef);
    }
  }

  @override
  void addSource(DartSource source) {
    // Has no effect in binding generator
  }

  /// Define a bridged top-level function declaration.
  @override
  void defineBridgeTopLevelFunction(BridgeFunctionDeclaration function) {
    final libraryDeclarations = _bridgeDeclarations[function.library];
    if (libraryDeclarations == null) {
      _bridgeDeclarations[function.library] = [function];
    } else {
      libraryDeclarations.add(function);
    }
  }

  /// Define a set of unresolved bridge classes
  void defineBridgeClasses(List<BridgeClassDef> classDefs) {
    for (final classDef in classDefs) {
      defineBridgeClass(classDef);
    }
  }

  @override
  void addExportedLibraryMapping(String libraryUri, String exportUri) {
    _exportedLibMappings[libraryUri] = exportUri;
  }

  /// Generate binding code for a class/enum/function from an external library,
  /// without requiring @Bind annotations.
  ///
  /// This is the config-driven counterpart of [parse]. Instead of scanning
  /// source files for @Bind annotations, it resolves the element by name from
  /// the library's export namespace and generates the binding directly.
  Future<String?> parseFromConfig({
    required String libraryUri,
    required String className,
    required String overrideLibrary,
    bool isBridge = false,
    List<String> externMembers = const [],
    String filePrefix = '',
  }) async {
    _contextCollection ??= AnalysisContextCollection(
      includedPaths: includedPaths,
      resourceProvider: Bindgen.resourceProvider,
    );

    // Resolve the library and find the element by name
    final context = _contextCollection!.contexts.first;
    final session = context.currentSession;
    final libResult = await session.getLibraryByUri(libraryUri);
    if (libResult is! LibraryElementResult) {
      print('Warning: Could not resolve library $libraryUri');
      return null;
    }
    final libElement = libResult.element;
    final element = libElement.exportNamespace.get2(className);
    if (element == null) {
      print('Warning: $className not found in $libraryUri');
      return null;
    }

    // Skip generic types — bindgen generates $T.wrap() but $T doesn't exist
    final hasTypeParams = switch (element) {
      InterfaceElement2 e => e.typeParameters2.isNotEmpty,
      TopLevelFunctionElement e => e.typeParameters2.isNotEmpty,
      _ => false,
    };
    if (hasTypeParams) {
      print('Warning: Skipping $className from $libraryUri '
          '(generic types not yet supported)');
      return null;
    }

    // Use the element's actual defining library URI for the type spec.
    // For re-exported types (e.g. Container exported from
    // package:flutter/widgets.dart but defined in
    // package:flutter/src/widgets/container.dart), this ensures $spec
    // uses the correct internal URI that the dart_eval runtime expects.
    final actualUri = element.library2?.uri.toString() ?? overrideLibrary;

    final evalFilename = '${_toSnakeCase(className)}.eval.dart';
    final registeredFile = filePrefix.isEmpty
        ? evalFilename
        : '$filePrefix/$evalFilename';
    final ctx = BindgenContext(evalFilename, overrideLibrary,
        all: true,
        bridgeDeclarations: _bridgeDeclarations,
        exportedLibMappings: _exportedLibMappings);
    ctx.libOverrides[className] = actualUri;
    ctx.externMembers.addAll(externMembers);
    ctx.implicitSupers = false;

    String? code;
    if (element is ClassElement2) {
      if (isBridge && element.isSealed) {
        throw CompileError(
            'Cannot bind sealed class $className as a bridge type.');
      }
      registerClasses.add((
        file: registeredFile,
        uri: actualUri,
        name: '$className${isBridge ? '\$bridge' : ''}',
      ));
      code = _generateInstance(ctx, element, isBridge: isBridge);
    } else if (element is EnumElement2) {
      registerEnums.add((
        file: registeredFile,
        uri: actualUri,
        name: className,
      ));
      code = _generateEnum(ctx, element);
    } else if (element is TopLevelFunctionElement) {
      registerFunctions.add((
        file: registeredFile,
        uri: actualUri,
        name: className,
      ));
      code = _generateFunction(ctx, element);
    }

    if (code == null) return null;

    // Assemble output with imports
    final imports = ctx.imports
        .whereNot((e) => e == overrideLibrary)
        .map((e) => "import '$e';")
        .join('\n');
    return '$imports$code';
  }

  /// Generate instance (class) binding code, shared by parse() and
  /// parseFromConfig().
  String _generateInstance(
      BindgenContext ctx, ClassElement2 element,
      {required bool isBridge}) {
    if (isBridge) {
      return '''
/// dart_eval bridge binding for [${element.name3}]
class \$${element.name3}\$bridge extends ${element.name3} with \$Bridge<${element.name3}> {
${bindForwardedConstructors(ctx, element)}
/// Configure this class for use in a [Runtime]
${bindConfigureForRuntime(ctx, element, isBridge: true)}
/// Compile-time type specification of [\$${element.name3}\$bridge]
${bindTypeSpec(ctx, element)}
/// Compile-time type declaration of [\$${element.name3}\$bridge]
${bindBridgeType(ctx, element)}
/// Compile-time class declaration of [\$${element.name3}]
${bindBridgeDeclaration(ctx, element, isBridge: true)}
${$constructors(ctx, element, isBridge: true)}
${$staticMethods(ctx, element)}
${$staticGetters(ctx, element)}
${$staticSetters(ctx, element)}
${$bridgeGet(ctx, element)}
${$bridgeSet(ctx, element)}
${bindDecoratorProperties(ctx, element)}
${bindDecoratorMethods(ctx, element)}
}
''';
    }

    return '''
/// dart_eval wrapper binding for [${element.name3}]
class \$${element.name3} implements \$Instance {
/// Configure this class for use in a [Runtime]
${bindConfigureForRuntime(ctx, element)}
/// Compile-time type specification of [\$${element.name3}]
${bindTypeSpec(ctx, element)}
/// Compile-time type declaration of [\$${element.name3}]
${bindBridgeType(ctx, element)}
/// Compile-time class declaration of [\$${element.name3}]
${bindBridgeDeclaration(ctx, element)}
${$constructors(ctx, element)}
${$staticMethods(ctx, element)}
${$staticGetters(ctx, element)}
${$staticSetters(ctx, element)}
${$wrap(ctx, element)}
${$getRuntimeType(element)}
${$getProperty(ctx, element)}
${$methods(ctx, element)}
${$setProperty(ctx, element)}
}
''';
  }

  /// Generate enum binding code, shared by parse() and parseFromConfig().
  String _generateEnum(BindgenContext ctx, EnumElement2 element) {
    return '''
/// dart_eval enum wrapper binding for [${element.name3}]
class \$${element.name3} implements \$Instance {
  /// Configure this enum for use in a [Runtime]
  ${bindConfigureEnumForRuntime(ctx, element)}
  /// Compile-time type specification of [\$${element.name3}]
  ${bindTypeSpec(ctx, element)}
  /// Compile-time type declaration of [\$${element.name3}]
  ${bindBridgeType(ctx, element)}
  /// Compile-time class declaration of [\$${element.name3}]
  ${bindBridgeDeclaration(ctx, element)}
  ${$enumValues(ctx, element)}
  ${$staticMethods(ctx, element)}
  ${$staticGetters(ctx, element)}
  ${$staticSetters(ctx, element)}
  ${$wrap(ctx, element)}
  ${$getRuntimeType(element)}
  ${$getProperty(ctx, element)}
  ${$methods(ctx, element)}
  ${$setProperty(ctx, element)}
}
''';
  }

  /// Generate top-level function binding code, shared by parse() and
  /// parseFromConfig().
  String _generateFunction(
      BindgenContext ctx, TopLevelFunctionElement element) {
    return '''
/// dart_eval function wrapper binding for [${element.name3}]
class \$${element.name3}Fn implements EvalCallable {
  const \$${element.name3}Fn();

  ${bindConfigureFunctionForRuntime(ctx, element)}
  ${bindFunctionDeclaration(ctx, element)}
  ${$function(ctx, element)}
}
''';
  }

  static String _toSnakeCase(String input) {
    return input
        .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(
            RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase();
  }

  Future<String?> parse(io.File src, String filename, String uri, bool all,
      {bool separateOutputDir = false, String filePrefix = ''}) async {
    final resourceProvider = PhysicalResourceProvider.INSTANCE;
    if (_contextCollection == null) {
      _contextCollection = AnalysisContextCollection(
        includedPaths: includedPaths,
        resourceProvider: resourceProvider,
      );
      print('Analyzing project source...');
    }

    final filePath = src.path;
    final analysisContext = _contextCollection!.contextFor(filePath);
    final session = analysisContext.currentSession;
    final analysisResult = await session.getResolvedUnit(filePath);
    final evalFilename = filename.replaceAll('.dart', '.eval.dart');
    final registeredFile = filePrefix.isEmpty
        ? evalFilename
        : '$filePrefix/$evalFilename';
    final ctx = BindgenContext(filename, uri,
        all: all,
        registeredFile: registeredFile,
        bridgeDeclarations: _bridgeDeclarations,
        exportedLibMappings: _exportedLibMappings);

    if (analysisResult is ResolvedUnitResult) {
      // Access the resolved unit and analyze it

      final evalOutput = filename.replaceAll('.dart', '.eval.dart');
      bool partOf = false;

      if (!all &&
          analysisResult.unit.directives.any((element) =>
              element is PartDirective &&
              element.uri.stringValue == evalOutput)) {
        partOf = true;
      } else {
        for (final directive in analysisResult.unit.directives) {
          if (directive is ImportDirective) {
            var importUri = directive.uri.stringValue;
            if (importUri == null ||
                importUri.startsWith('package:eval_annotation')) {
              continue;
            }
            // When output dir differs from source dir, relative imports
            // would break. Resolve them to absolute package URIs.
            if (separateOutputDir &&
                !importUri.startsWith('package:') &&
                !importUri.startsWith('dart:')) {
              importUri = Uri.parse(uri).resolve(importUri).toString();
            }
            ctx.imports.add(importUri);
          }
        }
      }

      final units = analysisResult.unit.declarations;

      final Iterable<String> resolved;
      try {
        resolved = units
            .where((declaration) => declaration.declaredFragment != null)
            .map((declaration) {
              if (declaration is ClassDeclaration) {
                return _$instance(ctx, declaration.declaredFragment!.element);
              } else if (declaration is EnumDeclaration) {
                return _$enum(ctx, declaration.declaredFragment!.element);
              } else if (declaration is FunctionDeclaration) {
                return _$function(ctx, declaration.declaredFragment!.element);
              }
              return null;
            })
            .toList()
            .nonNulls;
      } on Error {
        print('Failed to resolve $filePath:');
        rethrow;
      }

      if (resolved.isEmpty) {
        return null;
      }

      final result = resolved.join('\n');
      final imports = ctx.imports
          .whereNot((e) => e == uri)
          .map((e) => 'import \'$e\';')
          .join('\n');

      return partOf ? "part of '$filename'" : "$imports$result";
    }

    return null;
  }

  ({bool process, bool isBridge, bool alsoWrap}) _shouldProcess(
      BindgenContext ctx, Annotatable element) {
    final metadata = element.metadata2;
    final bindAnno = metadata.annotations
        .firstWhereOrNull((element) => element.element2?.displayName == 'Bind');
    final bindAnnoValue = bindAnno?.computeConstantValue();

    if (bindAnnoValue == null && !ctx.all) {
      return (process: false, isBridge: false, alsoWrap: false);
    }
    final implicitSupers =
        bindAnnoValue?.getField('implicitSupers')?.toBoolValue() ?? false;
    ctx.implicitSupers = implicitSupers;
    final override = bindAnnoValue?.getField('overrideLibrary');
    if (override != null && !override.isNull && element is Element2) {
      final overrideUri = override.toStringValue();
      if (overrideUri != null) {
        ctx.libOverrides[(element as Element2).name3!] = overrideUri;
      }
    }

    final isBridge = bindAnnoValue?.getField('bridge')?.toBoolValue() ?? false;
    final alsoWrap = bindAnnoValue?.getField('wrap')?.toBoolValue() ?? false;

    return (
      process: ctx.all || bindAnnoValue != null,
      isBridge: isBridge,
      alsoWrap: alsoWrap,
    );
  }

  /// Scan static members of [element] for @Bind(extern: true) annotation
  /// and add their names to [ctx.externMembers].
  void _collectExternMembers(BindgenContext ctx, InterfaceElement element) {
    for (final getter in element.getters) {
      if (getter.isStatic && !getter.isPrivate && _isExternAnnotated(getter)) {
        ctx.externMembers.add(getter.name!);
      }
    }
    for (final method in element.methods) {
      if (method.isStatic && !method.isPrivate && _isExternAnnotated(method)) {
        ctx.externMembers.add(method.name!);
      }
    }
    for (final setter in element.setters) {
      if (setter.isStatic && !setter.isPrivate && _isExternAnnotated(setter)) {
        ctx.externMembers.add(setter.name!);
      }
    }
  }

  /// Check if an element has @Bind(extern: true) annotation.
  bool _isExternAnnotated(Element element) {
    final metadata = element.metadata;
    final bindAnno = metadata.annotations
        .firstWhereOrNull((e) => e.element?.displayName == 'Bind');
    if (bindAnno == null) return false;
    final value = bindAnno.computeConstantValue();
    return value?.getField('extern')?.toBoolValue() ?? false;
  }

  String? _$instance(BindgenContext ctx, ClassElement2 element) {
    final (:process, :isBridge, :alsoWrap) = _shouldProcess(ctx, element);
    if (!process) {
      return null;
    }

    if (isBridge && element.isSealed) {
      throw CompileError(
          'Cannot bind sealed class ${element.name3} as a bridge type. '
          'Please remove the @Bind annotation, use a wrapper, or make the class non-sealed.');
    }

    // Scan members for @Bind(extern: true) and record in ctx.externMembers
    ctx.externMembers.clear();
    _collectExternMembers(ctx, element);

    registerClasses.add((
      file: ctx.registeredFile.isEmpty
          ? ctx.filename.replaceAll('.dart', '.eval.dart')
          : ctx.registeredFile,
      uri: ctx.libOverrides[element.name3!] ?? ctx.uri,
      name: '${element.name3!}${isBridge ? '\$bridge' : ''}',
    ));

    String code = _generateInstance(ctx, element, isBridge: isBridge);

    if (isBridge && alsoWrap) {
      // Add a rudimentary wrapper, because you cannot wrap things in a bridge.
      code += '''
/// dart_eval wrapper binding for [${element.name3}]
class \$${element.name3} implements \$Instance {
/// Compile-time type specification of [\$${element.name3}]
${bindTypeSpec(ctx, element)}
/// Compile-time type declaration of [\$${element.name3}]
${bindTypeSpec(ctx, element)}
${$wrap(ctx, element)}
${$getRuntimeType(element)}
${$getProperty(ctx, element)}
${$methods(ctx, element)}
${$setProperty(ctx, element)}
}
''';
    }

    return code;
  }

  String? _$enum(BindgenContext ctx, EnumElement2 element) {
    final (:process, :isBridge, :alsoWrap) = _shouldProcess(ctx, element);
    if (!process) {
      return null;
    }

    // Clear stale extern members from a previously processed class/enum
    ctx.externMembers.clear();

    registerEnums.add((
      file: ctx.registeredFile.isEmpty
          ? ctx.filename.replaceAll('.dart', '.eval.dart')
          : ctx.registeredFile,
      uri: ctx.libOverrides[element.name3!] ?? ctx.uri,
      name: element.name3!,
    ));

    return _generateEnum(ctx, element);
  }

  String? _$function(BindgenContext ctx, ExecutableElement2 element) {
    if (element is! TopLevelFunctionElement) return null;
    final (:process, :isBridge, :alsoWrap) = _shouldProcess(ctx, element);
    if (!process) {
      return null;
    }

    registerFunctions.add((
      file: ctx.registeredFile.isEmpty
          ? ctx.filename.replaceAll('.dart', '.eval.dart')
          : ctx.registeredFile,
      uri: ctx.libOverrides[element.name3!] ?? ctx.uri,
      name: element.name3!,
    ));

    return _generateFunction(ctx, element);
  }

  String $superclassWrapper(BindgenContext ctx, InterfaceElement2 element) {
    final supertype = element.supertype;
    final objectWrapper = '\$Object(\$value)';
    if (supertype == null || ctx.implicitSupers || element is EnumElement2) {
      ctx.imports.add('package:dart_eval/stdlib/core.dart');
      return objectWrapper;
    }
    final narrowWrapper = wrapType(ctx, supertype, '\$value');
    if (narrowWrapper == null) {
      print('Warning: Could not wrap supertype $supertype of ${element.name3},'
          ' falling back to \$Object. Add a @Bind annotation to $supertype'
          ' or set `implicitSupers: true`');
      ctx.imports.add('package:dart_eval/stdlib/core.dart');
      return objectWrapper;
    }
    return narrowWrapper;
  }

  String $getRuntimeType(InterfaceElement2 element) {
    return '''
  @override
  int \$getRuntimeType(Runtime runtime) => runtime.lookupType(\$spec);
''';
  }

  String $wrap(BindgenContext ctx, InterfaceElement2 element) {
    return '''
  final \$Instance _superclass;

  @override
  final ${element.name3} \$value;

  @override
  ${element.name3} get \$reified => \$value;

  /// Wrap a [${element.name3}] in a [\$${element.name3}]
  \$${element.name3}.wrap(this.\$value) : _superclass = ${$superclassWrapper(ctx, element)};
    ''';
  }
}
