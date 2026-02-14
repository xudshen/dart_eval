part of '../type.dart';

/// Abstract base class for return type representations in the compiler.
///
/// Return types may be statically known ([AlwaysReturnType]),
/// bridged ([BridgedReturnType]), or dependent on parameter types
/// ([ParameterTypeDependentReturnType]) or type arguments
/// ([TargetTypeArgDependentReturnType], [TypeArgDependentReturnType]).
abstract class ReturnType {
  AlwaysReturnType? toAlwaysReturnType(CompilerContext ctx, TypeRef? targetType,
      List<TypeRef?> argTypes, Map<String, TypeRef?> namedArgTypes,
      {List<TypeRef> typeArgs = const []});
}

class BridgedReturnType implements ReturnType {
  final BridgeTypeSpec spec;
  final bool nullable;

  BridgedReturnType(this.spec, this.nullable);

  @override
  AlwaysReturnType? toAlwaysReturnType(CompilerContext ctx, TypeRef? targetType,
      List<TypeRef?> argTypes, Map<String, TypeRef?> namedArgTypes,
      {List<TypeRef> typeArgs = const []}) {
    final rt = TypeRef.fromBridgeTypeRef(ctx, BridgeTypeRef(spec));
    return AlwaysReturnType(rt, nullable);
  }
}

class AlwaysReturnType implements ReturnType {
  const AlwaysReturnType(this.type, this.nullable);

  factory AlwaysReturnType.fromAnnotation(CompilerContext ctx, int library,
      TypeAnnotation? typeAnnotation, TypeRef? fallback) {
    final rt = typeAnnotation;
    if (rt != null) {
      return AlwaysReturnType(
          TypeRef.fromAnnotation(ctx, library, rt), rt.question != null);
    } else {
      return AlwaysReturnType(fallback, true);
    }
  }

  factory AlwaysReturnType.fromInstanceMethod(
      CompilerContext ctx, TypeRef type, String method, TypeRef? fallback) {
    final m = resolveInstanceMethod(ctx, type, method);
    if (m.isBridge) {
      return AlwaysReturnType(
          TypeRef.fromBridgeAnnotation(
              ctx, m.bridge!.functionDescriptor.returns),
          true);
    }
    return AlwaysReturnType.fromAnnotation(
        ctx, type.file, m.declaration!.returnType, fallback);
  }

  factory AlwaysReturnType.fromStaticMethod(
      CompilerContext ctx, TypeRef type, String method, TypeRef? fallback) {
    final m = resolveStaticMethod(ctx, type, method);
    if (m.isBridge) {
      if (m.bridge is! BridgeMethodDef) {
        return AlwaysReturnType(CoreTypes.dynamic.ref(ctx), true);
      }
      final fn = (m.bridge as BridgeMethodDef).functionDescriptor;
      return AlwaysReturnType(
          TypeRef.fromBridgeAnnotation(ctx, fn.returns), fn.returns.nullable);
    }
    final d = m.declaration!;
    if (d is ConstructorDeclaration) {
      return AlwaysReturnType(type, false);
    }
    if (d is MethodDeclaration) {
      return AlwaysReturnType.fromAnnotation(
          ctx, type.file, d.returnType, fallback);
    }
    // Fallback for non-method declarations (e.g. VariableDeclaration)
    return AlwaysReturnType(fallback ?? CoreTypes.dynamic.ref(ctx), true);
  }

  static AlwaysReturnType? fromInstanceMethodOrBuiltin(
      CompilerContext ctx,
      TypeRef type,
      String method,
      List<TypeRef?> argTypes,
      Map<String, TypeRef?> namedArgTypes,
      {List<TypeRef> typeArgs = const [],
      bool $static = false}) {
    final resolvedType = type.resolveTypeChain(ctx);
    final knownType = resolvedType.extendsType == CoreTypes.enumType.ref(ctx)
        ? CoreTypes.enumType.ref(ctx)
        : resolvedType;
    if (!$static &&
        getKnownMethods(ctx)[knownType] != null &&
        getKnownMethods(ctx)[knownType]!.containsKey(method)) {
      final knownMethod = getKnownMethods(ctx)[knownType]![method]!;
      final returnType = knownMethod.returnType;
      if (returnType == null) {
        return null;
      }
      return returnType.toAlwaysReturnType(
          ctx, knownType, argTypes, namedArgTypes,
          typeArgs: typeArgs);
    }

    if (type == CoreTypes.dynamic.ref(ctx)) {
      return AlwaysReturnType(CoreTypes.dynamic.ref(ctx), true);
    }

    return $static
        ? AlwaysReturnType.fromStaticMethod(
            ctx, type, method, CoreTypes.dynamic.ref(ctx))
        : AlwaysReturnType.fromInstanceMethod(
            ctx, type, method, CoreTypes.dynamic.ref(ctx));
  }

  final TypeRef? type;
  final bool nullable;

  @override
  AlwaysReturnType? toAlwaysReturnType(CompilerContext ctx, TypeRef? targetType,
      List<TypeRef?> argTypes, Map<String, TypeRef?> namedArgTypes,
      {List<TypeRef> typeArgs = const []}) {
    return this;
  }
}

class ParameterTypeDependentReturnType implements ReturnType {
  const ParameterTypeDependentReturnType(this.map,
      {this.paramIndex, this.paramName, this.fallback});

  final int? paramIndex;
  final String? paramName;
  final Map<TypeRef, AlwaysReturnType> map;
  final AlwaysReturnType? fallback;

  @override
  AlwaysReturnType? toAlwaysReturnType(CompilerContext ctx, TypeRef? targetType,
      List<TypeRef?> argTypes, Map<String, TypeRef?> namedArgTypes,
      {List<TypeRef> typeArgs = const []}) {
    AlwaysReturnType? resolvedType;
    if (paramIndex != null) {
      resolvedType = map[argTypes[paramIndex!]];
    } else if (paramName != null) {
      resolvedType = map[namedArgTypes[paramName]];
    }

    if (resolvedType == null) {
      return fallback;
    }
    return resolvedType;
  }
}

class TargetTypeArgDependentReturnType implements ReturnType {
  const TargetTypeArgDependentReturnType(this.typeArgIndex);

  final int typeArgIndex;

  @override
  AlwaysReturnType? toAlwaysReturnType(CompilerContext ctx, TypeRef? targetType,
      List<TypeRef?> argTypes, Map<String, TypeRef?> namedArgTypes,
      {List<TypeRef> typeArgs = const []}) {
    return AlwaysReturnType(targetType!.specifiedTypeArgs[typeArgIndex], false);
  }
}

class TypeArgDependentReturnType implements ReturnType {
  const TypeArgDependentReturnType(this.typeArgIndex);

  final int typeArgIndex;

  @override
  AlwaysReturnType? toAlwaysReturnType(CompilerContext ctx, TypeRef? targetType,
      List<TypeRef?> argTypes, Map<String, TypeRef?> namedArgTypes,
      {List<TypeRef> typeArgs = const []}) {
    return AlwaysReturnType(typeArgs[typeArgIndex], false);
  }
}
