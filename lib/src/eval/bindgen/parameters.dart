import 'package:analyzer/dart/element/element2.dart';
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
  return List.generate(
      params.length, (index) => _parameterFrom(ctx, params[index])).join('\n');
}

String _parameterFrom(BindgenContext ctx, FormalParameterElement parameter) {
  return '''
    BridgeParameter(
      '${parameter.name3}',
      ${bridgeTypeAnnotationFrom(ctx, parameter.type)},
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
    paramBuffer.write('(args[$idx]! as EvalCallable$q)$call(runtime, null, [');
    if (type is FunctionType) {
      for (var j = 0; j < type.formalParameters.length; j++) {
        final ftParam = type.formalParameters[j];
        final name = ftParam.name3 == null || ftParam.name3!.isEmpty
            ? 'arg$j'
            : ftParam.name3!;
        paramBuffer
            .write(wrapVar(ctx, ftParam.type, name, forCollection: true));
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
      paramBuffer.write(')$q.cast${castTypeArgsSuffix(type)}()');
    }
  }
  return paramBuffer.toString();
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
      .toList();
}
