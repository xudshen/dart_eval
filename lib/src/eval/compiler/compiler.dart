import 'package:analyzer/dart/ast/ast.dart';
import 'package:collection/collection.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/declaration/declaration.dart';
import 'package:dart_eval/src/eval/compiler/declaration/field.dart';
import 'package:dart_eval/src/eval/compiler/model/diagnostic_mode.dart';
import 'package:dart_eval/src/eval/compiler/model/library.dart';
import 'package:dart_eval/src/eval/compiler/source.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/program.dart';
import 'package:dart_eval/src/eval/bridge/declaration.dart';
import 'package:dart_eval/src/eval/compiler/model/compilation_unit.dart';
import 'package:dart_eval/src/eval/compiler/util.dart';
import 'package:dart_eval/src/eval/compiler/util/custom_crawler.dart';
import 'package:dart_eval/src/eval/compiler/util/graph.dart';
import 'package:dart_eval/src/eval/compiler/util/library_graph.dart';
import 'package:dart_eval/src/eval/compiler/util/tree_shake.dart';
import 'package:dart_eval/src/eval/shared/stdlib/async.dart';
import 'package:dart_eval/src/eval/shared/stdlib/collection.dart';
import 'package:dart_eval/src/eval/shared/stdlib/convert.dart';
import 'package:dart_eval/src/eval/shared/stdlib/core.dart';
import 'package:dart_eval/src/eval/shared/stdlib/io.dart';
import 'package:dart_eval/src/eval/shared/stdlib/math.dart';
import 'package:dart_eval/src/eval/shared/stdlib/typed_data.dart';
import 'package:directed_graph/directed_graph.dart';

import 'context.dart';
import 'debug/scope_dump.dart';
import 'errors.dart';

part 'phases/parse_phase.dart';
part 'phases/link_phase.dart';
part 'phases/compile_phase.dart';
part 'phases/emit_phase.dart';

/// Compiles Dart source code into EVC bytecode, outputting a [Program].
///
/// To use, call [compile] or [compileSources].
///
/// You may define bridge libraries using a combination of [defineBridgeClass],
/// [defineBridgeTopLevelFunction], and [defineBridgeEnum].
///
/// Additional sources can be added with [addSource].
class Compiler implements BridgeDeclarationRegistry, EvalPluginRegistry {
  var _bridgeStaticFunctionIdx = 0;
  final _bridgeDeclarations = <String, List<BridgeDeclaration>>{};

  /// A map of library IDs / indexes to a map of String declaration names to
  /// [DeclarationOrBridge]s. Populated in [_populateLookupTablesForDeclaration]
  /// and copied to [CompilerContext.topLevelDeclarationsMap].
  var _topLevelDeclarationsMap = <int, Map<String, DeclarationOrBridge>>{};
  var _topLevelGlobalIndices = <int, Map<String, int>>{};
  var _instanceDeclarationsMap = <int, Map<String, Map<String, Declaration>>>{};

  /// The semantic version of the compiled code, for runtime overrides
  String? version;

  var _ctx = CompilerContext(0);

  /// List of additional [DartSource] files to be compiled when [compile] is run
  final additionalSources = <DartSource>[];
  final _cachedParsedSources = <DartSource, DartCompilationUnit>{};

  /// [EvalPlugin]s that will be applied to the compiler
  final _plugins = <EvalPlugin>[
    DartAsyncPlugin(),
    DartCollectionPlugin(),
    DartConvertPlugin(),
    DartCorePlugin(),
    DartIoPlugin(),
    DartMathPlugin(),
    DartTypedDataPlugin()
  ];
  final _appliedPlugins = <String>[];

  /// List of files whose functions should be used as entrypoints. These can be
  /// full URIs (e.g. `package:foo/main.dart`) or just filenames (e.g.
  /// `main.dart`). Adding a file to this list prevents it from being dead-code
  /// eliminated.
  final entrypoints = ['/main.dart'];

  /// The diagnostic mode to use when parsing.
  var diagnosticMode = DiagnosticMode.throwIfError;

  // Add a plugin, which will only be run once.
  @override
  void addPlugin(EvalPlugin plugin) {
    _plugins.add(plugin);
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

  /// Define a bridged enum definition to be used when compiling.
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

  /// Add a unit source to the list of additional sources which will be compiled
  /// alongside the packages specified in [compile].
  @override
  void addSource(DartSource source) => additionalSources.add(source);

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

  /// A list of libraries that have been bridged
  List<String> get bridgedLibraries => _bridgeDeclarations.keys.toList();

  /// Compile a set of Dart code into a program. Shorthand for
  /// [compileSources]. Code should be specified in a map as such:
  /// ```
  /// {
  ///   'package_name': {
  ///     'file_name1.dart': '''code''',
  ///     'file_name2.dart': '''code'''
  ///   }
  /// }
  ///```
  Program compile(Map<String, Map<String, String>> packages,
      {ScopeRecorder? scopeRecorder}) {
    final sources = packages.entries.expand((packageEntry) =>
        packageEntry.value.entries.map((library) => DartSource(
            'package:${packageEntry.key}/${library.key}', library.value)));

    return compileSources(sources, true, scopeRecorder);
  }

  /// Compile a unit set of Dart code into a program.
  ///
  /// Orchestrates 4 compilation phases:
  /// 1. Parse — convert sources into AST compilation units
  /// 2. Link — build libraries, merge bridges, resolve imports/exports
  /// 3. Compile — compile declarations into bytecode
  /// 4. Emit — resolve types and produce the final [Program]
  Program compileSources(
      [Iterable<DartSource> sources = const [],
      bool debugPerf = true,
      ScopeRecorder? scopeRecorder]) {
    _topLevelDeclarationsMap = <int, Map<String, DeclarationOrBridge>>{};
    _topLevelGlobalIndices = <int, Map<String, int>>{};
    _instanceDeclarationsMap = <int, Map<String, Map<String, Declaration>>>{};
    _bridgeStaticFunctionIdx = 0;

    // Create a compilation context
    _ctx = CompilerContext(0, version: version);
    if (scopeRecorder != null) {
      _ctx.scopeRecorder = scopeRecorder;
    }

    for (final plugin in _plugins) {
      if (!_appliedPlugins.contains(plugin.identifier)) {
        plugin.configureForCompile(this);
        _appliedPlugins.add(plugin.identifier);
      }
    }

    // Phase 1: Parse sources into AST compilation units
    final units = _parseSources(
        sources, additionalSources, _cachedParsedSources, diagnosticMode);

    // Phase 2: Link — build libraries, merge bridges, resolve imports/exports,
    // populate lookup tables, cache type refs, compute visible types
    final linkResult = _linkLibraries(
      units,
      _ctx,
      _bridgeDeclarations,
      entrypoints,
      _topLevelDeclarationsMap,
      _instanceDeclarationsMap,
      _topLevelGlobalIndices,
      _populateLookupTablesForDeclaration,
      _cacheTypeRef,
    );

    // Wire link results into context
    _ctx.topLevelDeclarationsMap = _topLevelDeclarationsMap;
    _ctx.instanceDeclarationsMap = _instanceDeclarationsMap;
    _ctx.visibleDeclarations = linkResult.visibleDeclarationsByIndex;
    _ctx.visibleTypes = linkResult.visibleTypesByIndex;

    // Resolve typedef aliases: now that visibleTypes is populated,
    // map each typedef name to the TypeRef of its aliased type.
    _resolveTypeAliases();

    unboxedAcrossFunctionBoundaries = {
      CoreTypes.int.ref(_ctx),
      CoreTypes.double.ref(_ctx),
      CoreTypes.bool.ref(_ctx),
      CoreTypes.list.ref(_ctx)
    };

    // Assign bridge static function indices
    for (final library in linkResult.reachableLibraries) {
      final libraryIndex = linkResult.libraryIndexMap[library]!;
      for (final dec in library.declarations) {
        if (dec.isBridge) {
          final bridge = dec.bridge;
          if (bridge is BridgeClassDef) {
            _assignBridgeStaticFunctionIndicesForClass(bridge);
          } else if (bridge is BridgeEnumDef) {
            _assignBridgeGlobalValueIndicesForEnum(bridge);
          } else if (bridge is BridgeFunctionDeclaration) {
            _assignBridgeStaticFunctionIndicesForFunction(libraryIndex, bridge);
          }
        }
      }
    }

    _ctx.topLevelGlobalIndices = _topLevelGlobalIndices;

    // Phase 3: Compile all declarations into bytecode
    _compileDeclarations(_ctx, _topLevelDeclarationsMap,
        _instanceDeclarationsMap, linkResult.visibleDeclarationsByIndex);

    // Phase 4: Emit the final Program
    return _emitProgram(
        _ctx, linkResult.libraryIndexMap, linkResult.reachableLibraries);
  }

  /// For testing purposes. Compile code, write it to a byte stream, load it,
  /// and run it.
  Runtime compileWriteAndLoad(Map<String, Map<String, String>> packages,
      {ScopeRecorder? scopeRecorder}) {
    final program = compile(packages, scopeRecorder: scopeRecorder);

    final ob = program.write();

    return Runtime(ob.buffer.asByteData());
  }

  void _populateLookupTablesForDeclaration(
      int libraryIndex, DeclarationOrBridge declarationOrBridge) {
    if (!_topLevelDeclarationsMap.containsKey(libraryIndex)) {
      _topLevelDeclarationsMap[libraryIndex] = {};
    }

    if (!_instanceDeclarationsMap.containsKey(libraryIndex)) {
      _instanceDeclarationsMap[libraryIndex] = {};
    }

    if (declarationOrBridge.isBridge) {
      final bridge = declarationOrBridge.bridge!;
      if (bridge is BridgeClassDef) {
        final spec = bridge.type.type.spec!;
        _topLevelDeclarationsMap[libraryIndex]![spec.name] =
            DeclarationOrBridge(libraryIndex, bridge: bridge);
        for (final constructor in bridge.constructors.entries) {
          _topLevelDeclarationsMap[libraryIndex]![
                  '${spec.name}.${constructor.key}'] =
              DeclarationOrBridge(libraryIndex, bridge: constructor.value);
        }
        for (final method in bridge.methods.entries) {
          if (method.value.isStatic) {
            _topLevelDeclarationsMap[libraryIndex]![
                    '${spec.name}.${method.key}'] =
                DeclarationOrBridge(libraryIndex, bridge: method.value);
          }
        }
      } else if (bridge is BridgeEnumDef) {
        final spec = bridge.type.spec!;
        _topLevelDeclarationsMap[libraryIndex]![spec.name] =
            DeclarationOrBridge(libraryIndex, bridge: bridge);
      } else if (bridge is BridgeFunctionDeclaration) {
        _topLevelDeclarationsMap[libraryIndex]![bridge.name] =
            DeclarationOrBridge(libraryIndex, bridge: bridge);
      }
      return;
    }

    final declaration = declarationOrBridge.declaration!;

    if (declaration is TopLevelVariableDeclaration) {
      final vlist = declaration.variables;

      if (!_topLevelGlobalIndices.containsKey(libraryIndex)) {
        _topLevelGlobalIndices[libraryIndex] = {};
        _ctx.topLevelGlobalInitializers[libraryIndex] = {};
        _ctx.topLevelVariableInferredTypes[libraryIndex] = {};
      }

      for (final variable in vlist.variables) {
        final name = variable.name.lexeme;

        if (_topLevelDeclarationsMap[libraryIndex]!.containsKey(name)) {
          throw CompileError('Cannot define "$name" twice in the same library',
              variable, libraryIndex);
        }

        _topLevelDeclarationsMap[libraryIndex]![name] =
            DeclarationOrBridge(libraryIndex, declaration: variable);
        _topLevelGlobalIndices[libraryIndex]![name] = _ctx.globalIndex++;
      }
    } else {
      declaration as NamedCompilationUnitMember;
      final name = declaration.name.lexeme;

      if (_topLevelDeclarationsMap[libraryIndex]!.containsKey(name)) {
        throw CompileError('Cannot define "$name" twice in the same library',
            declaration, libraryIndex);
      }

      _topLevelDeclarationsMap[libraryIndex]![name] =
          DeclarationOrBridge(libraryIndex, declaration: declaration);

      if (declaration is ClassDeclaration ||
          declaration is EnumDeclaration ||
          declaration is MixinDeclaration) {
        _instanceDeclarationsMap[libraryIndex]![name] = {};
        final members = declaration is ClassDeclaration
            ? declaration.members
            : declaration is MixinDeclaration
                ? declaration.members
                : (declaration as EnumDeclaration).members;

        if (declaration is EnumDeclaration) {
          _ctx.enumValueIndices[libraryIndex] ??= {};
          _ctx.enumValueIndices[libraryIndex]![declaration.name.lexeme] = {};
          for (final constant in declaration.constants) {
            if (!_topLevelGlobalIndices.containsKey(libraryIndex)) {
              _topLevelGlobalIndices[libraryIndex] = {};
              _ctx.topLevelGlobalInitializers[libraryIndex] = {};
              _ctx.topLevelVariableInferredTypes[libraryIndex] = {};
            }
            final name = '${declaration.name.lexeme}.${constant.name.lexeme}';
            if (_topLevelDeclarationsMap[libraryIndex]!.containsKey(name)) {
              throw CompileError(
                  'Cannot define "$name" twice in the same library',
                  constant,
                  libraryIndex);
            }

            _topLevelDeclarationsMap[libraryIndex]![name] =
                DeclarationOrBridge(libraryIndex, declaration: constant);
            final globalIndex = _ctx.globalIndex++;
            _topLevelGlobalIndices[libraryIndex]![name] = globalIndex;
            _ctx.enumValueIndices[libraryIndex]![declaration.name.lexeme]![
                constant.name.lexeme] = globalIndex;
          }
        }

        for (var member in members) {
          if (member is MethodDeclaration) {
            var mName = member.name.lexeme;
            if (member.isStatic) {
              _topLevelDeclarationsMap[libraryIndex]!['$name.$mName'] =
                  DeclarationOrBridge(libraryIndex, declaration: member);
            } else {
              if (member.isGetter) {
                mName += '*g';
              } else if (member.isSetter) {
                mName += '*s';
              }
              _instanceDeclarationsMap[libraryIndex]![name]![mName] = member;
            }
          } else if (member is FieldDeclaration) {
            if (member.isStatic) {
              if (!_topLevelGlobalIndices.containsKey(libraryIndex)) {
                _topLevelGlobalIndices[libraryIndex] = {};
                _ctx.topLevelGlobalInitializers[libraryIndex] = {};
                _ctx.topLevelVariableInferredTypes[libraryIndex] = {};
              }

              for (final field in member.fields.variables) {
                final name = '${declaration.name.lexeme}.${field.name.lexeme}';

                if (_topLevelDeclarationsMap[libraryIndex]!.containsKey(name)) {
                  throw CompileError(
                      'Cannot define "$name" twice in the same library',
                      field,
                      libraryIndex);
                }

                _topLevelDeclarationsMap[libraryIndex]![name] =
                    DeclarationOrBridge(libraryIndex, declaration: field);
                _topLevelGlobalIndices[libraryIndex]![name] =
                    _ctx.globalIndex++;
              }
            } else {
              for (final field in member.fields.variables) {
                final fName = field.name.lexeme;
                _instanceDeclarationsMap[libraryIndex]![name]![fName] = field;
              }
            }
          } else if (member is ConstructorDeclaration) {
            final mName = (member.name?.lexeme) ?? "";
            _topLevelDeclarationsMap[libraryIndex]!['$name.$mName'] =
                DeclarationOrBridge(libraryIndex, declaration: member);
          } else {
            throw CompileError(
                'Not a NamedCompilationUnitMember', member, libraryIndex);
          }
        }
      }
    }
  }

  TypeRef? _cacheTypeRef(
      int libraryIndex, DeclarationOrBridge declarationOrBridge) {
    if (declarationOrBridge.isBridge) {
      final bridge = declarationOrBridge.bridge;
      if (bridge is! BridgeClassDef && bridge is! BridgeEnumDef) {
        return null;
      }
      final type = bridge is BridgeClassDef
          ? bridge.type.type
          : (bridge as BridgeEnumDef).type;
      if (type.cacheId != null) {
        return TypeRef.fromBridgeTypeRef(_ctx, type);
      }
      final spec = type.spec!;
      return TypeRef.cache(_ctx, libraryIndex, spec.name,
          fileRef: libraryIndex);
    } else {
      final declaration = declarationOrBridge.declaration!;
      if (declaration is! ClassDeclaration &&
          declaration is! EnumDeclaration &&
          declaration is! MixinDeclaration) {
        return null;
      }
      final name = (declaration as NamedCompilationUnitMember).name.lexeme;
      return TypeRef.cache(_ctx, libraryIndex, name, fileRef: libraryIndex);
    }
  }

  /// Resolve typedef aliases after visibleTypes is populated.
  ///
  /// For each [GenericTypeAlias] in the declarations, resolve its target
  /// type and register the alias name in [_ctx.visibleTypes] so that
  /// [TypeRef.fromAnnotation] can find it.
  void _resolveTypeAliases() {
    for (final entry in _topLevelDeclarationsMap.entries) {
      final libraryIndex = entry.key;
      for (final decEntry in entry.value.entries) {
        final dob = decEntry.value;
        if (dob.isBridge) continue;
        final declaration = dob.declaration;
        if (declaration is! GenericTypeAlias) continue;

        final aliasedType = declaration.type;
        _ctx.visibleTypes[libraryIndex] ??= {};

        if (aliasedType is GenericFunctionType) {
          _ctx.visibleTypes[libraryIndex]![declaration.name.lexeme] =
              CoreTypes.function.ref(_ctx);
        } else if (aliasedType is NamedType) {
          // Resolve named type alias (e.g. typedef StringList = List<String>)
          _ctx.library = libraryIndex;
          try {
            final resolved =
                TypeRef.fromAnnotation(_ctx, libraryIndex, aliasedType);
            _ctx.visibleTypes[libraryIndex]![declaration.name.lexeme] = resolved;
          } catch (_) {
            // If the target type can't be resolved, skip this typedef
          }
        }
      }
    }
  }

  void _assignBridgeStaticFunctionIndicesForClass(BridgeClassDef classDef) {
    final type = TypeRef.fromBridgeTypeRef(_ctx, classDef.type.type);
    final lib = type.file;
    if (!_ctx.bridgeStaticFunctionIndices.containsKey(lib)) {
      _ctx.bridgeStaticFunctionIndices[lib] = <String, int>{};
    }
    classDef.constructors.forEach((name, constructor) {
      if (!_ctx.bridgeStaticFunctionIndices.containsKey(lib)) {
        _ctx.bridgeStaticFunctionIndices[lib] = <String, int>{};
      }
      _ctx.bridgeStaticFunctionIndices[lib]!['${type.name}.$name'] =
          _bridgeStaticFunctionIdx++;
    });

    classDef.methods.forEach((name, method) {
      if (!method.isStatic) return;
      if (!_ctx.bridgeStaticFunctionIndices.containsKey(lib)) {
        _ctx.bridgeStaticFunctionIndices[lib] = <String, int>{};
      }
      _ctx.bridgeStaticFunctionIndices[lib]!['${type.name}.$name'] =
          _bridgeStaticFunctionIdx++;
    });

    classDef.getters.forEach((name, getter) {
      if (!getter.isStatic) return;
      if (!_ctx.bridgeStaticFunctionIndices.containsKey(lib)) {
        _ctx.bridgeStaticFunctionIndices[lib] = <String, int>{};
      }
      _ctx.bridgeStaticFunctionIndices[lib]!['${type.name}.$name*g'] =
          _bridgeStaticFunctionIdx++;
    });

    classDef.setters.forEach((name, setter) {
      if (!setter.isStatic) return;
      if (!_ctx.bridgeStaticFunctionIndices.containsKey(lib)) {
        _ctx.bridgeStaticFunctionIndices[lib] = <String, int>{};
      }
      _ctx.bridgeStaticFunctionIndices[lib]!['${type.name}.$name*s'] =
          _bridgeStaticFunctionIdx++;
    });

    classDef.fields.forEach((name, field) {
      if (!field.isStatic) return;
      if (!_ctx.bridgeStaticFunctionIndices.containsKey(lib)) {
        _ctx.bridgeStaticFunctionIndices[lib] = <String, int>{};
      }
      _ctx.bridgeStaticFunctionIndices[lib]!['${type.name}.$name*g'] =
          _bridgeStaticFunctionIdx++;
      _ctx.bridgeStaticFunctionIndices[lib]!['${type.name}.$name*s'] =
          _bridgeStaticFunctionIdx++;
    });
  }

  void _assignBridgeGlobalValueIndicesForEnum(BridgeEnumDef enumDef) {
    final type = TypeRef.fromBridgeTypeRef(_ctx, enumDef.type);
    final lib = type.file;
    if (!_ctx.enumValueIndices.containsKey(lib)) {
      _ctx.enumValueIndices[lib] = {};
    }
    _ctx.enumValueIndices[lib]![type.name] = {
      for (final value in enumDef.values) value: _ctx.globalIndex++
    };
  }

  void _assignBridgeStaticFunctionIndicesForFunction(
      int libraryIndex, BridgeFunctionDeclaration functionDef) {
    if (!_ctx.bridgeStaticFunctionIndices.containsKey(libraryIndex)) {
      _ctx.bridgeStaticFunctionIndices[libraryIndex] = <String, int>{};
    }
    _ctx.bridgeStaticFunctionIndices[libraryIndex]![functionDef.name] =
        _bridgeStaticFunctionIdx++;
  }

  @override
  void addExportedLibraryMapping(String libraryUri, String exportUri) {
    // does nothing in compiler context
  }
}
