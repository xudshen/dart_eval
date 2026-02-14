import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/declaration/constructor.dart';
import 'package:dart_eval/src/eval/compiler/declaration/declaration.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';

void compileClassDeclaration(CompilerContext ctx, ClassDeclaration d,
    {bool statics = false}) {
  // Load class-level type parameters (e.g. T in class Foo<T>) so they
  // resolve to dynamic during member compilation
  TypeRef.loadTemporaryTypes(ctx, d.typeParameters?.typeParameters);

  final $runtimeType =
      ctx.typeRefIndexMap[TypeRef.lookupDeclaration(ctx, ctx.library, d)];
  final clsName = d.name.lexeme;
  ctx.instanceDeclarationPositions[ctx.library]![clsName] = [
    {},
    {},
    {},
    $runtimeType
  ];
  ctx.instanceGetterIndices[ctx.library]![clsName] = {};
  final constructors = <ConstructorDeclaration>[];
  final fields = <FieldDeclaration>[];
  final methods = <MethodDeclaration>[];
  for (final m in d.members) {
    if (m is ConstructorDeclaration) {
      constructors.add(m);
    } else if (m is FieldDeclaration) {
      if (!m.isStatic) {
        fields.add(m);
      }
    } else {
      m as MethodDeclaration;
      methods.add(m);
    }
  }
  var i = 0;
  if (constructors.isEmpty) {
    ctx.resetStack(position: 0);
    ctx.currentClass = d;
    compileDefaultConstructor(ctx, d, fields);
  }
  for (final m in <ClassMember>[...fields, ...methods, ...constructors]) {
    ctx.resetStack(
        position: m is ConstructorDeclaration ||
                (m is MethodDeclaration && m.isStatic)
            ? 0
            : 1);
    ctx.currentClass = d;
    compileDeclaration(m, ctx, parent: d, fieldIndex: i, fields: fields);
    if (m is FieldDeclaration) {
      i += m.fields.variables.length;
    }
  }
  // Merge mixin methods into this class's instance declaration positions
  if (d.withClause != null) {
    final classPositions =
        ctx.instanceDeclarationPositions[ctx.library]![clsName]!;
    final classGetterIndices =
        ctx.instanceGetterIndices[ctx.library]![clsName]!;
    for (final mixinType in d.withClause!.mixinTypes) {
      final mixinName = mixinType.name2.lexeme;
      final mixinPositions =
          ctx.instanceDeclarationPositions[ctx.library]?[mixinName];
      if (mixinPositions == null) continue;
      // Merge getters (index 0), setters (index 1), methods (index 2)
      for (var idx = 0; idx < 3; idx++) {
        final mixinMap = mixinPositions[idx] as Map;
        final classMap = classPositions[idx] as Map;
        for (final entry in mixinMap.entries) {
          classMap.putIfAbsent(entry.key, () => entry.value);
        }
      }
      // Merge getter indices
      final mixinGetterIndices =
          ctx.instanceGetterIndices[ctx.library]?[mixinName];
      if (mixinGetterIndices != null) {
        for (final entry in mixinGetterIndices.entries) {
          classGetterIndices.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
  }
  ctx.currentClass = null;
  ctx.temporaryTypes[ctx.library]?.clear();
  ctx.resetStack();
}

/// Compile a mixin application: `class C = A with M1, M2;`
///
/// ClassTypeAlias automatically inherits constructors from its superclass
/// and merges instance members from both superclass and mixins.
void compileClassTypeAliasDeclaration(CompilerContext ctx, ClassTypeAlias d) {
  TypeRef.loadTemporaryTypes(ctx, d.typeParameters?.typeParameters);

  final $runtimeType =
      ctx.typeRefIndexMap[TypeRef.lookupDeclaration(ctx, ctx.library, d)];
  final clsName = d.name.lexeme;
  ctx.instanceDeclarationPositions[ctx.library]![clsName] = [
    {},
    {},
    {},
    $runtimeType
  ];
  ctx.instanceGetterIndices[ctx.library]![clsName] = {};

  // Alias C's constructor positions to the superclass's constructor positions.
  // In Dart, `class C = A with M;` inherits all of A's constructors.
  // The aliased constructor creates a superclass-typed instance — this is
  // imperfect but sufficient for most use cases.
  final superName = d.superclass.name2.lexeme;
  final superDecl = ctx.topLevelDeclarationsMap[ctx.library]?[superName];
  if (superDecl != null && !superDecl.isBridge) {
    final superClass = superDecl.declaration;
    if (superClass is ClassDeclaration) {
      final constructors =
          superClass.members.whereType<ConstructorDeclaration>().toList();
      if (constructors.isEmpty) {
        // Super has implicit default constructor — alias C. → A.
        final superPos =
            ctx.topLevelDeclarationPositions[ctx.library]?['$superName.'];
        if (superPos != null) {
          ctx.topLevelDeclarationPositions[ctx.library]!['$clsName.'] =
              superPos;
        }
      } else {
        for (final ctor in constructors) {
          final ctorName = ctor.name?.lexeme ?? '';
          final superPos = ctx.topLevelDeclarationPositions[ctx.library]
              ?['$superName.$ctorName'];
          if (superPos != null) {
            ctx.topLevelDeclarationPositions[ctx.library]![
                '$clsName.$ctorName'] = superPos;
          }
        }
      }
    } else if (superClass is ClassTypeAlias) {
      // Chained mixin application: class C = B with M2; class B = A with M1;
      // Copy any constructor positions already registered for the super alias.
      final positions = ctx.topLevelDeclarationPositions[ctx.library];
      if (positions != null) {
        for (final key in positions.keys.toList()) {
          if (key.startsWith('$superName.')) {
            final ctorSuffix = key.substring(superName.length);
            positions['$clsName$ctorSuffix'] = positions[key]!;
          }
        }
      }
    }
  } else {
    // Bridge superclass or not found — compile a default constructor
    ctx.resetStack(position: 0);
    ctx.currentClass = d;
    compileDefaultConstructor(ctx, d, []);
  }

  // Merge superclass instance members
  _mergeInstanceMembers(ctx, clsName, superName);

  // Merge mixin instance members (mixins override superclass on conflict)
  for (final mixinType in d.withClause.mixinTypes) {
    final mixinName = mixinType.name2.lexeme;
    _mergeInstanceMembers(ctx, clsName, mixinName);
  }

  ctx.currentClass = null;
  ctx.temporaryTypes[ctx.library]?.clear();
  ctx.resetStack();
}

/// Merge instance getters/setters/methods from [sourceName] into [targetName].
void _mergeInstanceMembers(
    CompilerContext ctx, String targetName, String sourceName) {
  final sourcePositions =
      ctx.instanceDeclarationPositions[ctx.library]?[sourceName];
  if (sourcePositions == null) return;

  final targetPositions =
      ctx.instanceDeclarationPositions[ctx.library]![targetName]!;
  final targetGetterIndices =
      ctx.instanceGetterIndices[ctx.library]![targetName]!;

  // Merge getters (0), setters (1), methods (2)
  for (var idx = 0; idx < 3; idx++) {
    final sourceMap = sourcePositions[idx] as Map;
    final targetMap = targetPositions[idx] as Map;
    for (final entry in sourceMap.entries) {
      targetMap.putIfAbsent(entry.key, () => entry.value);
    }
  }

  final sourceGetterIndices =
      ctx.instanceGetterIndices[ctx.library]?[sourceName];
  if (sourceGetterIndices != null) {
    for (final entry in sourceGetterIndices.entries) {
      targetGetterIndices.putIfAbsent(entry.key, () => entry.value);
    }
  }
}
