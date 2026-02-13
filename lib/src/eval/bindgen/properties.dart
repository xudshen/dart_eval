import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dart_eval/src/eval/bindgen/context.dart';
import 'package:dart_eval/src/eval/bindgen/operator.dart';
import 'package:dart_eval/src/eval/bindgen/parameters.dart';
import 'package:dart_eval/src/eval/bindgen/permission.dart';
import 'package:dart_eval/src/eval/bindgen/type.dart';

String $getProperty(BindgenContext ctx, InterfaceElement2 element) {
  return '''
  @override
  \$Value? \$getProperty(Runtime runtime, String identifier) {
    ${propertyGetters(ctx, element)}
    return _superclass.\$getProperty(runtime, identifier);
  }
''';
}

String $bridgeGet(BindgenContext ctx, ClassElement2 element) {
  return '''
  @override
  \$Value? \$bridgeGet(String identifier) {
    ${propertyGetters(ctx, element, isBridge: true)}
    return null;
  }
''';
}

String propertyGetters(BindgenContext ctx, InterfaceElement2 element,
    {bool isBridge = false}) {
  final methods = {
    if (ctx.implicitSupers)
      for (var s in element.allSupertypes)
        for (final m in s.element3.methods2) m.name3: m,
    for (final m in element.methods2) m.name3: m
  };
  final gettersMap = {
    if (ctx.implicitSupers)
      for (var s in element.allSupertypes)
        for (final g in s.element3.getters2) g.name3: g,
    for (final g in element.getters2) g.name3: g
  };
  final getters = gettersMap.values
      .where((accessor) => !accessor.isStatic && !accessor.isPrivate)
      .where((a) => !(const ['hashCode', 'runtimeType'].contains(a.name3)));

  final methods0 = methods.values
      .where((method) => !method.isPrivate && !method.isStatic)
      .where(
          (m) => !(const ['==', 'toString', 'noSuchMethod'].contains(m.name3)))
      // For bridge $bridgeGet: skip abstract methods — super.abstract() is
      // invalid. Abstract methods are handled by bindDecoratorMethods via
      // $_invoke instead.
      .where((m) => !isBridge || !m.isAbstract);
  if (getters.isEmpty && methods0.isEmpty) {
    return '';
  }
  if (isBridge) {
    return 'switch (identifier) {\n${getters.map((e) {
      final wrapped = wrapVar(ctx, e.type.returnType, '_${e.displayName}', metadata: e.metadata2.annotations);
      if (wrapped == wrapVarSkipSentinel) return '';
      return '''
      case '${e.displayName}':
        final _${e.displayName} = super.${e.displayName};
        return $wrapped;
      ''';
    }).where((s) => s.isNotEmpty).join('\n')}${methods0.map((e) {
      final returnWrapped = wrapVar(ctx, e.returnType, 'result');
      if (returnWrapped == wrapVarSkipSentinel) return '';
      final returnsValue =
          e.returnType is! VoidType && !e.returnType.isDartCoreNull;
      final op = resolveMethodOperator(e.displayName);
      return '''
        case '${e.displayName}':
          return \$Function((runtime, target, args) {
            ${assertMethodPermissions(e)}
            ${returnsValue ? 'final result = ' : ''}${op.format('super', argumentAccessors(ctx, e.formalParameters, isBridgeMethod: false))};
            return $returnWrapped;
          });''';
    }).where((s) => s.isNotEmpty).join('\n')}\n}';
  }
  return 'switch (identifier) {\n${getters.map((e) {
      final wrapped = wrapVar(ctx, e.type.returnType, '_${e.name3}', metadata: e.metadata2.annotations);
      if (wrapped == wrapVarSkipSentinel) return '';
      return '''
      case '${e.name3}':
        final _${e.name3} = \$value.${e.name3};
        return $wrapped;
      ''';
    }).where((s) => s.isNotEmpty).join('\n')}${methods0.map((e) {
      // Check if the method's return type is bound — if not, the method
      // was skipped in $methods() and __methodName won't exist.
      final returnWrapped = wrapVar(ctx, e.returnType, 'result');
      if (returnWrapped == wrapVarSkipSentinel) return '';
      return '''
      case '${e.name3}':
        return __${resolveMethodOperator(e.displayName).name};
      ''';
    }).where((s) => s.isNotEmpty).join('\n')}\n}';
}

String $setProperty(BindgenContext ctx, InterfaceElement2 element) {
  return '''
  @override
  void \$setProperty(Runtime runtime, String identifier, \$Value value) {
    ${propertySetters(ctx, element)}
    return _superclass.\$setProperty(runtime, identifier, value);
  }
''';
}

String $bridgeSet(BindgenContext ctx, ClassElement2 element) {
  return '''
  @override
  void \$bridgeSet(String identifier, \$Value value) {
    ${propertySetters(ctx, element, isBridge: true)}
  }
''';
}

String propertySetters(BindgenContext ctx, InterfaceElement2 element,
    {bool isBridge = false}) {
  final setters = element.setters2
      .where((element) => !element.isStatic && !element.isPrivate);
  if (setters.isEmpty) {
    return '';
  }
  if (isBridge) {
    return 'switch (identifier) {\n${setters.map((e) => '''
        case '${e.displayName}':
          super.${e.displayName} = value.\$reified;
          return;
        ''').join('\n')}\n}';
  }
  return 'switch (identifier) {\n${setters.map((e) => '''
        case '${e.displayName}':
          \$value.${e.displayName} = value.\$reified;
          return;
        ''').join('\n')}\n}';
}
