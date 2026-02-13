import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';

/// Discovered dependency with its source library URI.
class TypeDependency {
  final String name;
  final String libraryUri;
  final bool isEnum;

  TypeDependency({
    required this.name,
    required this.libraryUri,
    required this.isEnum,
  });

  @override
  bool operator ==(Object other) =>
      other is TypeDependency &&
      other.name == name &&
      other.libraryUri == libraryUri;

  @override
  int get hashCode => Object.hash(name, libraryUri);

  @override
  String toString() => 'TypeDependency($name from $libraryUri)';
}

/// Analyze a class's API surface (constructor params, method return types,
/// method params, getter/property types) and return types that are NOT in
/// [knownTypes] and NOT in [excludeTypes].
///
/// Types from `dart:core`, `dart:async`, `dart:collection`, `dart:convert`,
/// `dart:io`, `dart:math`, and `dart:typed_data` are skipped because
/// dart_eval provides built-in wrappers for them.
///
/// Generic types (with type parameters) are skipped because bindgen cannot
/// auto-generate bindings for them.
Set<TypeDependency> collectDependencyTypes(
  InterfaceElement2 element, {
  required Set<String> knownTypes,
  required Set<String> excludeTypes,
}) {
  final deps = <TypeDependency>{};

  /// SDK libraries that dart_eval provides built-in wrappers for.
  const sdkLibsWithBuiltinWrappers = {
    'dart:core',
    'dart:async',
    'dart:collection',
    'dart:convert',
    'dart:io',
    'dart:math',
    'dart:typed_data',
  };

  void visit(DartType type) {
    // Skip non-interesting types
    if (type is VoidType || type is DynamicType || type is NeverType) return;
    if (type.isDartCoreNull) return;

    // For function types, recurse into return type and parameter types
    if (type is FunctionType) {
      visit(type.returnType);
      for (final param in type.formalParameters) {
        visit(param.type);
      }
      return;
    }

    // Generic type parameters (T, E, etc.) are handled separately
    if (type is TypeParameterType) return;

    final el = type.element3;
    if (el == null) return;
    final name = el.name3;
    if (name == null || name.startsWith('_')) return; // Private type
    if (knownTypes.contains(name)) return;
    if (excludeTypes.contains(name)) return;

    final lib = el.library2;
    if (lib == null) return;

    // Skip SDK types that have built-in wrappers in dart_eval
    if (lib.isInSdk) {
      final uri = lib.uri.toString();
      if (sdkLibsWithBuiltinWrappers.contains(uri)) {
        return;
      }
    }

    // Skip generic types (can't auto-generate bindings for them)
    if (el is InterfaceElement2 && el.typeParameters2.isNotEmpty) return;

    final isEnum = el is EnumElement2;
    deps.add(TypeDependency(
      name: name,
      libraryUri: lib.uri.toString(),
      isEnum: isEnum,
    ));

    // Recurse into type arguments (e.g. List<ColorScheme> → visit ColorScheme)
    if (type is ParameterizedType) {
      for (final arg in type.typeArguments) {
        visit(arg);
      }
    }
  }

  // Scan constructors
  for (final cstr in element.constructors2) {
    if (cstr.isPrivate) continue;
    for (final param in cstr.formalParameters) {
      visit(param.type);
    }
  }

  // Scan getters/properties
  for (final getter in element.getters2) {
    if (getter.isPrivate || getter.isStatic) continue;
    visit(getter.type.returnType);
  }

  // Scan methods
  for (final method in element.methods2) {
    if (method.isPrivate || method.isStatic) continue;
    visit(method.returnType);
    for (final param in method.formalParameters) {
      visit(param.type);
    }
  }

  // Scan fields (covers final fields that may not have explicit getters)
  for (final field in element.fields2) {
    if (field.isPrivate || field.isStatic) continue;
    visit(field.type);
  }

  // Scan supertypes (the superclass and implemented interfaces)
  final supertype = element.supertype;
  if (supertype != null) {
    visit(supertype);
  }

  return deps;
}
