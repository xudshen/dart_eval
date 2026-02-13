import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:change_case/change_case.dart';
import 'package:collection/collection.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/bindgen/context.dart';
import 'package:dart_eval/src/eval/bindgen/errors.dart';
import 'package:dart_eval/src/eval/bindgen/parameters.dart';
import 'package:path/path.dart' as path;

/// Sentinel returned by [wrapVar] when a type has no binding and the member
/// should be skipped rather than generating a runtime.wrapAlways() fallback.
const wrapVarSkipSentinel = '__SKIP__UNBOUND_TYPE__';

String bridgeTypeRefFromType(BindgenContext ctx, DartType type) {
  if (type is TypeParameterType) {
    return 'BridgeTypeRef.ref(\'${type.element3.name3}\')';
  } else if (type is FunctionType) {
    return '''BridgeTypeRef.genericFunction(BridgeFunctionDef(
      returns: ${bridgeTypeAnnotationFrom(ctx, type.returnType)},
      params: [
        ${parameters(ctx, type.formalParameters.where((p) => p.isPositional).toList())}
      ],
      namedParams: [
        ${parameters(ctx, type.formalParameters.where((p) => p.isNamed).toList())}
      ],
    ))''';
  } else if (type is ParameterizedType) {
    final typeArgs = type.typeArguments
        .map((e) => bridgeTypeAnnotationFrom(ctx, e))
        .join(', ');
    return 'BridgeTypeRef(${bridgeTypeSpecFrom(ctx, type)}, [$typeArgs])';
  }
  return 'BridgeTypeRef(${bridgeTypeSpecFrom(ctx, type)})';
}

String bridgeTypeAnnotationFrom(BindgenContext ctx, DartType type) {
  final nullabilityString = type.nullabilitySuffix == NullabilitySuffix.question
      ? ', nullable: true'
      : '';
  return 'BridgeTypeAnnotation(${bridgeTypeRefFromType(ctx, type)}$nullabilityString)';
}

String bridgeTypeSpecFrom(BindgenContext ctx, DartType type) {
  final builtin = builtinTypeFrom(type);
  if (builtin != null) {
    return builtin;
  }
  final element = type.element3!;
  final lib = element.library2!;
  final uri = ctx.libOverrides[element.name3] ?? lib.uri.toString();
  return 'BridgeTypeSpec(\'$uri\', \'${element.name3!.replaceAll(r'$', r'\$')}\')';
}

String? builtinTypeFrom(DartType type) {
  if (type.isDartCoreNull) {
    return 'CoreTypes.nullType';
  }
  if (type.isDartCoreEnum) {
    return 'CoreTypes.enumType';
  }
  if (type is VoidType) {
    return 'CoreTypes.voidType';
  }
  if (type is DynamicType) {
    return 'CoreTypes.dynamic';
  }
  if (type is FunctionType) {
    return 'CoreTypes.function';
  }
  if (type is RecordType) {
    return 'CoreTypes.record';
  }
  if (type is NeverType) {
    return 'CoreTypes.never';
  }

  final element = type.element3!;
  final lib = element.library2!;
  final name = element.name3 ?? ' ';
  final lowerCamelCaseName = name.toCamelCase();

  if (!lib.isInSdk) {
    return null;
  }

  final uri = lib.uri.toString();

  if (uri == 'dart:async') {
    if (name == 'Future' || name == 'Stream') {
      return 'CoreTypes.$lowerCamelCaseName';
    }
    // FutureOr is a special type without an AsyncTypes constant.
    if (name == 'FutureOr') return null;
    return 'AsyncTypes.$lowerCamelCaseName';
  }
  if (uri == 'dart:collection') {
    return 'CollectionTypes.$lowerCamelCaseName';
  }
  if (uri == 'dart:convert') {
    return 'ConvertTypes.$lowerCamelCaseName';
  }
  if (uri == 'dart:core') {
    return 'CoreTypes.$lowerCamelCaseName';
  }
  if (uri == 'dart:io') {
    return 'IoTypes.$lowerCamelCaseName';
  }
  if (uri == 'dart:math') {
    return 'MathTypes.$lowerCamelCaseName';
  }
  if (uri == 'dart:typed_data') {
    // Only these 4 types have TypedDataTypes constants in dart_eval.
    const validTypedDataTypes = {
      'ByteBuffer', 'TypedData', 'ByteData', 'Uint8List'
    };
    if (validTypedDataTypes.contains(name)) {
      return 'TypedDataTypes.$lowerCamelCaseName';
    }
    return null;
  }
  return null;
}

String? wrapVar(BindgenContext ctx, DartType type, String expr,
    {bool func = false,
    bool wrapList = false,
    List<ElementAnnotation>? metadata,
    bool forCollection = false,
    String runtimeExpr = 'runtime'}) {
  if (type is VoidType || type is NeverType) {
    if (func) {
      ctx.imports.add('package:dart_eval/stdlib/core.dart');
      return 'const \$null()';
    }
    return 'null';
  }

  if (type.isDartCoreNull) {
    ctx.imports.add('package:dart_eval/stdlib/core.dart');
    return 'const \$null()';
  }

  var wrapped =
      wrapType(ctx, type, expr, metadata: metadata, wrapList: wrapList);

  if (wrapped == null) {
    final typeName = type.element3?.name3 ?? type.getDisplayString();
    if (ctx.unknownTypes.add(typeName)) {
      print('Warning: type $typeName is not bound — '
          'member will be skipped');
    }
    return wrapVarSkipSentinel;
  }

  if (type.nullabilitySuffix == NullabilitySuffix.question) {
    ctx.imports.add('package:dart_eval/stdlib/core.dart');
    if (forCollection) {
      return 'if ($expr == null) const \$null() else $wrapped';
    }
    return '$expr == null ? const \$null() : $wrapped';
  }

  return wrapped;
}

String? wrapType(BindgenContext ctx, DartType type, String expr,
    {bool wrapList = false, List<ElementAnnotation>? metadata}) {
  final union =
      metadata?.firstWhereOrNull((e) => e.element2?.displayName == 'UnionOf');
  String unionStr = '';
  if (union != null) {
    final types =
        union.computeConstantValue()?.getField('types')?.toListValue();
    if (types != null && types.isNotEmpty) {
      for (final type in types) {
        final type0 = type.toTypeValue();
        if (type0 == null) {
          continue;
        }
        ctx.imports.add(type0.element3!.library2!.uri.toString());
        final wrapper = wrapVar(ctx, type0, expr);
        if (wrapper == wrapVarSkipSentinel) continue;

        unionStr += '$expr is ${type0.element3!.name3} ? $wrapper : ';
      }
    }
  }
  if (type is VoidType) {
    return '${unionStr}null';
  }

  if (type.isDartCoreNull) {
    ctx.imports.add('package:dart_eval/stdlib/core.dart');
    return '${unionStr}const \$null()';
  }

  if (type is DynamicType) {
    ctx.imports.add('package:dart_eval/stdlib/core.dart');
    return '$unionStr\$Object($expr)';
  }

  if (type is FunctionType) {
    final funcWrap = wrapFunctionType(ctx, type, expr);
    if (funcWrap == wrapVarSkipSentinel) return null;
    return unionStr + funcWrap;
  }

  if (type.isDartCoreFunction) {
    return '$unionStr\$Function((runtime, target, args) => $expr())';
  }

  final element = type.element3 ??
      (throw BindingGenerationError('Type $type has no element'));
  final lib = element.library2!;
  final name = element.name3 ?? ' ';

  final defaultCstr = {'int', 'num', 'double', 'bool', 'String', 'Object'};

  if (lib.isInSdk) {
    final dartUri = lib.uri.toString();
    final which = dartUri.substring(5);
    // Only use dart_eval stdlib for URIs it actually provides.
    // Other SDK libs (e.g. dart:ui from the Flutter engine) fall through
    // to the bridge declarations path below.
    const hasSdkStdlib = {
      'core', 'async', 'collection', 'convert', 'io', 'math', 'typed_data',
    };
    if (!hasSdkStdlib.contains(which)) {
      // Fall through — will be handled by bridgeDeclarations or wrapAlways()
    } else {
    ctx.imports.add('package:dart_eval/stdlib/$which.dart');
    if (defaultCstr.contains(name)) {
      return '$unionStr\$$name($expr)';
    }
    if (name == 'List') {
      if (wrapList) {
        return '$unionStr\$List.wrap($expr)';
      }
      final generic = type as ParameterizedType;
      final arg = generic.typeArguments.first;
      final innerWrap = wrapVar(ctx, arg, 'e');
      if (innerWrap == wrapVarSkipSentinel) return null;
      return '$unionStr\$List.view($expr, (e) => $innerWrap)';
    }
    if (name == 'Stream') {
      final generic = type as ParameterizedType;
      final arg = generic.typeArguments.first;
      final innerWrap = wrapVar(ctx, arg, 'e');
      if (innerWrap == wrapVarSkipSentinel) return null;
      return '$unionStr\$Stream.wrap($expr.map((e) => $innerWrap))';
    }
    if (name == 'Future') {
      final generic = type as ParameterizedType;
      final arg = generic.typeArguments.first;
      // Future<void> / Future<Null>: callback value is unusable, always
      // return const $null().
      if (arg is VoidType || arg.isDartCoreNull) {
        ctx.imports.add('package:dart_eval/stdlib/core.dart');
        return '$unionStr\$Future.wrap($expr.then((_) => const \$null()))';
      }
      final inner = wrapVar(ctx, arg, 'e');
      if (inner == wrapVarSkipSentinel) return null;
      // The Future value may be null at runtime (e.g. route pop without
      // result), even when the static type is non-nullable dynamic.
      // Guard with a null check so $Object(null) is never called.
      final body = arg is DynamicType
          ? 'e == null ? const \$null() : $inner'
          : inner;
      if (arg is DynamicType) {
        ctx.imports.add('package:dart_eval/stdlib/core.dart');
      }
      return '$unionStr\$Future.wrap($expr.then((e) => $body))';
    }
    // Types without dart_eval stdlib wrappers — fall through to
    // wrapAlways() via null return.
    const noStdlibWrapper = {'Type', 'FutureOr', 'Iterable', 'Iterator',
        'MapEntry', 'Pattern', 'Match', 'RegExp', 'Symbol', 'StackTrace',
        'Stopwatch', 'StringBuffer', 'StringSink', 'BidirectionalIterator',
        'Comparable'};
    if (noStdlibWrapper.contains(name)) {
      return null;
    }
    // dart:typed_data — only 4 types have stdlib wrappers.
    if (which == 'typed_data') {
      const typedDataWrappers = {
        'ByteBuffer', 'TypedData', 'ByteData', 'Uint8List'
      };
      if (!typedDataWrappers.contains(name)) {
        return null;
      }
    }
    return '$unionStr\$$name.wrap($expr)';
    } // end hasSdkStdlib else
  }

  final typeEl = type.element3!;
  if (typeEl is InterfaceElement2) {
    // Skip private types — they can't have public bindings
    if (name.startsWith('_')) return null;

    final uri = typeEl.library2.uri.toString();
    // Gate: this specific type is known to have bindings, either from
    // loaded JSON (bridgeDeclarations) or from @Bind annotation.
    // Check the specific type name, not just the library — a library
    // may have declarations for some types but not others.
    final libraryDecls = ctx.bridgeDeclarations[uri];
    final hasBridgeDecl = libraryDecls != null &&
        libraryDecls.any((d) {
          // Only wrapper-mode classes have $Name.wrap() — bridge-mode
          // classes use $Name$bridge and cannot wrap host instances.
          if (d is BridgeClassDef) {
            return d.type.type.spec?.name == name && d.wrap;
          }
          if (d is BridgeEnumDef) return d.type.spec?.name == name;
          return false;
        });
    final hasBindAnno = !hasBridgeDecl &&
        typeEl.metadata2.annotations
            .any((e) => e.element2?.displayName == 'Bind');
    if (hasBridgeDecl || hasBindAnno) {
      // First check per-type mapping (e.g. 'dart:ui#TextRange' → widgets barrel)
      // which handles types whose binding lives in a different barrel than
      // their source library.
      String? mappedUri = ctx.exportedLibMappings['$uri#$name'];

      // Fall back to library/directory walk-up
      if (mappedUri == null) {
        final parsedUri = Uri.parse(uri);
        String current = parsedUri.path;
        while (current != path.dirname(current)) {
          if (ctx.exportedLibMappings
              .containsKey('${parsedUri.scheme}:$current')) {
            mappedUri =
                ctx.exportedLibMappings['${parsedUri.scheme}:$current']!;
            break;
          }
          current = path.dirname(current);
        }
      }

      if (mappedUri != null) {
        ctx.imports.add(mappedUri);
        return '$unionStr\$$name.wrap($expr)';
      }
    }
  }

  if (type is TypeParameterType) {
    final bound = type.bound;
    if (bound is! DynamicType) {
      final b = wrapVar(ctx, bound, expr);
      if (b != null && b != wrapVarSkipSentinel) {
        return '$unionStr$b';
      }
    }
  }

  return null;
}

String wrapFunctionType(BindgenContext ctx, FunctionType type, String expr) {
  var buffer = StringBuffer('\$Function((runtime, target, args) { ');
  if (type.returnType is! VoidType && !type.returnType.isDartCoreNull) {
    buffer.write('final funcResult = ');
  }
  buffer.write('$expr(');
  var i = 0;
  for (; i < type.normalParameterTypes.length; i++) {
    buffer.write('args[$i]');
    final type0 = type.normalParameterTypes[i];
    if (type0.nullabilitySuffix == NullabilitySuffix.question) {
      buffer.write('?.\$value');
    } else {
      buffer.write('!.\$value');
    }
    if (i < type.normalParameterTypes.length - 1) {
      buffer.write(', ');
    }
  }

  if (type.optionalParameterTypes.isNotEmpty) {
    for (var j = i; j < type.optionalParameterTypes.length + i; j++) {
      if (type.normalParameterTypes.isNotEmpty) {
        buffer.write(', ');
      }
      final type0 = type.optionalParameterTypes[i];
      buffer.write('args[$j]');
      if (type0.nullabilitySuffix == NullabilitySuffix.question) {
        buffer.write('?.\$value');
      } else {
        buffer.write('!.\$value');
      }
      if (j < type.optionalParameterTypes.length + i - 1) {
        buffer.write(', ');
      }
    }
  }

  if (type.namedParameterTypes.isNotEmpty) {
    if (type.normalParameterTypes.isNotEmpty ||
        type.optionalParameterTypes.isNotEmpty) {
      buffer.write(', ');
    }

    var k = i;
    type.namedParameterTypes.forEach((npName, npType) {
      buffer.write(npName);
      buffer.write(': args[$k]');
      if (type.nullabilitySuffix == NullabilitySuffix.question) {
        buffer.write('?.\$value');
      } else {
        buffer.write('!.\$value');
      }
      if (k < type.namedParameterTypes.length + i - 1) {
        buffer.write(', ');
      }
    });
  }
  final returnWrap = wrapVar(ctx, type.returnType, 'funcResult', func: true);
  if (returnWrap == wrapVarSkipSentinel) return wrapVarSkipSentinel;
  buffer.write(
      '); return $returnWrap; })');
  return buffer.toString();
}

/// Returns the type argument suffix for `.cast()` on collection types.
///
/// For `Map<String, String>` returns `'<String, String>'`.
/// For unparameterized or all-dynamic types returns `''`.
///
/// When [ctx] is provided, adds imports for each type argument's defining
/// library so the generated `.cast<Widget>()` can find the `Widget` type.
String castTypeArgsSuffix(BindgenContext ctx, DartType type) {
  if (type is ParameterizedType) {
    final args = type.typeArguments;
    if (args.isNotEmpty && !args.every((a) => a is DynamicType)) {
      for (final arg in args) {
        if (arg is DynamicType) continue;
        final el = arg.element3;
        if (el != null) {
          final lib = el.library2;
          if (lib != null) {
            ctx.imports.add(lib.uri.toString());
          }
        }
      }
      return '<${args.map((a) => a.getDisplayString()).join(', ')}>';
    }
  }
  return '';
}

