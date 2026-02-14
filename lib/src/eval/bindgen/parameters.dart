import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:collection/collection.dart';
import 'package:dart_eval/src/eval/bindgen/bridge.dart';
import 'package:dart_eval/src/eval/bindgen/context.dart';
import 'package:dart_eval/src/eval/bindgen/type.dart';

String namedParameters(BindgenContext ctx,
    {required ExecutableElement2 element}) {
  final params = element.formalParameters.where((e) => e.isNamed);
  if (params.isEmpty) {
    return '';
  }

  return parameters(ctx, params.toList());
}

String positionalParameters(BindgenContext ctx,
    {required ExecutableElement2 element}) {
  final params = element.formalParameters.where((e) => e.isPositional);
  if (params.isEmpty) {
    return '';
  }

  return parameters(ctx, params.toList());
}

String parameters(BindgenContext ctx, List<FormalParameterElement> params) {
  return params.map((p) => _parameterFrom(ctx, p)).join('\n');
}

String _parameterFrom(BindgenContext ctx, FormalParameterElement parameter) {
  // Use dynamic type for parameters with unresolvable types to avoid
  // compiler errors while preserving correct parameter count/indices.
  final typeAnnotation = isTypeResolvable(ctx, parameter.type)
      ? bridgeTypeAnnotationFrom(ctx, parameter.type)
      : 'BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic, []))';
  return '''
    BridgeParameter(
      '${parameter.name3}',
      $typeAnnotation,
      ${parameter.isOptional ? 'true' : 'false'},
    ),
  ''';
}

String argumentAccessor(
    BindgenContext ctx, int index, FormalParameterElement param,
    {Map<String, String> paramMapping = const {},
    bool isBridgeMethod = false}) {
  final paramBuffer = StringBuffer();
  final idx = index + (isBridgeMethod ? 1 : 0);
  if (param.isNamed) {
    paramBuffer.write('${paramMapping[param.name3] ?? param.name3}: ');
  }
  final type = param.type;
  if (type.isDartCoreFunction || type is FunctionType) {
    // For nullable function-type params (both required and optional), guard
    // with null check so the closure is only created when the eval code
    // provides a callback value. Without this, required nullable callbacks
    // (e.g. `required VoidCallback? onPressed`) crash on `args[idx]!`, and
    // optional nullable callbacks would always be non-null, triggering
    // validation errors (e.g. GestureDetector rejects concurrent handlers).
    if (type.nullabilitySuffix == NullabilitySuffix.question) {
      paramBuffer.write('args[$idx] == null ? null : ');
    }
    // For optional non-nullable function-type params with defaults
    // (e.g. AppBar.notificationPredicate = defaultScrollNotificationPredicate),
    // skip entirely — let the Dart constructor use its default value.
    // Creating a closure would override the default, and args[idx] being null
    // (not passed by eval code) would crash on the non-null assertion.
    if (!param.isRequired &&
        type.nullabilitySuffix != NullabilitySuffix.question) {
      return '';
    }
    paramBuffer.write('(');
    if (type is FunctionType) {
      paramBuffer.write(parameterHeader(type.formalParameters));
      // Import libraries for callback parameter types so raw Dart type
      // names (e.g. TapMoveDetails) resolve in the generated file.
      for (final ftParam in type.formalParameters) {
        final ftEl = ftParam.type.element3;
        if (ftEl != null) {
          final ftLib = ftEl.library2;
          if (ftLib != null) {
            ctx.imports.add(ftLib.uri.toString());
          }
        }
      }
    }
    paramBuffer.write(') {\n');
    if (type is FunctionType) {
      if (type.returnType is! VoidType) {
        paramBuffer.write('return ');
      }
    }
    final q = (param.isRequired ? '' : '?');
    final call = (param.isRequired ? '' : '?.call');
    paramBuffer.write('(args[$idx]! as EvalCallable$q)$call(runtime, target, [');
    if (type is FunctionType) {
      for (var j = 0; j < type.formalParameters.length; j++) {
        final ftParam = type.formalParameters[j];
        final name = ftParam.name3 == null || ftParam.name3!.isEmpty
            ? 'arg$j'
            : ftParam.name3!;
        final wrapped =
            wrapVar(ctx, ftParam.type, name, forCollection: true);
        // For callback parameters flowing from Dart → eval, use $Object()
        // as a generic fallback when the specific type has no binding.
        if (wrapped == wrapVarSkipSentinel) {
          ctx.imports.add('package:dart_eval/stdlib/core.dart');
          if (ftParam.type.nullabilitySuffix == NullabilitySuffix.question) {
            paramBuffer.write(
                '$name == null ? const \$null() : \$Object($name)');
          } else {
            paramBuffer.write('\$Object($name)');
          }
        } else {
          paramBuffer.write(wrapped);
        }
        if (j < type.formalParameters.length - 1) {
          paramBuffer.write(', ');
        }
      }
    }
    paramBuffer.write('])');
    if (type is FunctionType) {
      if (type.returnType is! VoidType) {
        paramBuffer.write('?.\$value');
      }
    }
    paramBuffer.write(';\n}');
  } else {
    final needsCast =
        type.isDartCoreList || type.isDartCoreMap || type.isDartCoreSet;
    if (needsCast) {
      paramBuffer.write('(');
    }
    paramBuffer.write('args[$idx]');
    final accessor = needsCast ? 'reified' : 'value';
    if (param.isRequired) {
      paramBuffer.write('!.\$$accessor');
    } else {
      paramBuffer.write('?.\$$accessor');
      if (param.hasDefaultValue) {
        var defaultCode = param.defaultValueCode!;
        // Qualify unqualified static member references.
        // `defaultValueCode` gives source-level code (e.g. `strokeAlignInside`)
        // which only resolves inside the defining class. In our generated
        // wrapper class, prefix with the class name.
        if (!defaultCode.contains('.') && !_isLiteral(defaultCode)) {
          final enclosing = param.enclosingElement2?.enclosingElement2;
          if (enclosing is InterfaceElement2) {
            final hasStatic = enclosing.fields2.any(
                (f) => f.isStatic && f.name3 == defaultCode);
            if (hasStatic) {
              defaultCode = '${enclosing.name3}.$defaultCode';
            }
          }
        }
        // If the default value references a private member, skip this
        // parameter entirely — the Dart constructor will use its own default.
        // Private members are inaccessible from the generated wrapper file.
        if (_isPrivateDefault(defaultCode)) {
          return '';
        }
        // If default references a class not importable in the generated file
        // (e.g. CupertinoColors.systemBlue for a Color param), skip it.
        if (_isUnresolvableDefault(defaultCode, type)) {
          return '';
        }
        paramBuffer.write(' ?? $defaultCode');
        // Ensure the library defining the parameter's type is imported,
        // so default values like `DragStartBehavior.start` resolve.
        final typeEl = type.element3;
        if (typeEl != null) {
          final typeLib = typeEl.library2;
          if (typeLib != null) {
            ctx.imports.add(typeLib.uri.toString());
          }
        }
      }
    }
    if (needsCast) {
      final q = (param.isRequired ? '' : '?');
      paramBuffer.write(' as ${type.element3!.name3}$q');
      paramBuffer.write(')$q.cast${castTypeArgsSuffix(ctx, type)}()');
    }
  }
  return paramBuffer.toString();
}

/// Returns true if [code] references a private Dart member that would be
/// inaccessible from a generated wrapper file.
///
/// Detects top-level privates (e.g. `_snackBarDisplayDuration`), qualified
/// private members (e.g. `Tolerance._epsilonDefault`), and constructor calls
/// to private types (e.g. `const _DefaultHeroTag()`).
bool _isPrivateDefault(String code) {
  if (code.startsWith('_')) return true;
  if (code.contains('._')) return true;
  // Catch `const _Foo()` / `new _Bar()` patterns where a private identifier
  // appears after whitespace.
  if (RegExp(r'\s_[A-Za-z]').hasMatch(code)) return true;
  return false;
}

/// Returns true if a `ClassName.member` default value references a class
/// that isn't importable from the parameter type's library.
///
/// For example, `CupertinoColors.systemBlue` as default for a `Color`
/// parameter: `CupertinoColors` isn't defined in `dart:ui` (Color's library),
/// so it can't be resolved in the generated wrapper file.
bool _isUnresolvableDefault(String code, DartType type) {
  var cleaned = code;
  if (cleaned.startsWith('const ')) cleaned = cleaned.substring(6);
  final dotIdx = cleaned.indexOf('.');
  if (dotIdx <= 0) return false;
  final className = cleaned.substring(0, dotIdx);
  if (className.isEmpty ||
      className[0] != className[0].toUpperCase() ||
      _isLiteral(className)) {
    return false;
  }
  // If className matches the parameter type → self-reference, OK
  final typeName = type.element3?.name3;
  if (className == typeName) return false;
  // Check if className is exported by the parameter type's library
  final typeLib = type.element3?.library2;
  if (typeLib != null) {
    final classEl = typeLib.exportNamespace.get2(className);
    if (classEl != null) return false;
  }
  return true;
}

/// Returns true if [code] looks like a Dart literal (number, bool, null,
/// string, const expression, or collection literal).
bool _isLiteral(String code) {
  final c = code.trim();
  if (c == 'true' || c == 'false' || c == 'null') return true;
  if (c.startsWith("'") || c.startsWith('"')) return true;
  if (c.startsWith('const ') || c.startsWith('[') || c.startsWith('{')) {
    return true;
  }
  // Numeric literal (including hex like 0xFF000000)
  if (RegExp(r'^-?[0-9]').hasMatch(c)) return true;
  return false;
}

List<String> argumentAccessors(
    BindgenContext ctx, List<FormalParameterElement> params,
    {Map<String, String> paramMapping = const {},
    bool isBridgeMethod = false}) {
  return params
      .mapIndexed((i, p) => argumentAccessor(ctx, i, p,
          paramMapping: paramMapping, isBridgeMethod: isBridgeMethod))
      .where((s) => s.isNotEmpty)
      .toList();
}
