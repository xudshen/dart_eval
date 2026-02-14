import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/compiler/expression/method_invocation.dart';
import 'package:dart_eval/src/eval/compiler/helpers/argument_list.dart';
import 'package:dart_eval/src/eval/compiler/offset_tracker.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

Variable compileInstanceCreation(
    CompilerContext ctx, InstanceCreationExpression e) {
  final type = e.constructorName.type;
  final name = type.importPrefix == null
      ? (e.constructorName.name?.name ?? '')
      : type.name2.lexeme;
  final typeName = type.importPrefix?.name.lexeme ?? type.name2.lexeme;
  final $resolved = IdentifierReference(null, typeName).getValue(ctx);

  if ($resolved.concreteTypes.isEmpty) {
    throw CompileError('Cannot create instance of a non-type $typeName');
  }

  final staticType = $resolved.concreteTypes.first;

  // Check whether the constructor exists in the declaration map or bridge
  // indices. For implicit default constructors (class has no explicit
  // constructors), neither map will have the key because no
  // ConstructorDeclaration AST node exists. In that case, skip argument
  // compilation and emit a direct Call to the compiled default constructor.
  final constructorKey = '${staticType.name}.$name';
  final hasInDeclarations =
      ctx.topLevelDeclarationsMap[staticType.file]?.containsKey(constructorKey) ?? false;
  final hasInBridge =
      ctx.bridgeStaticFunctionIndices[staticType.file]?.containsKey(constructorKey) ?? false;

  if (!hasInDeclarations && !hasInBridge && name.isEmpty) {
    // Implicit default constructor — no parameters to compile.
    // Emit a Call to the constructor position (may be deferred).
    final offset = DeferredOrOffset.lookupStatic(
        ctx, staticType.file, staticType.name, name);
    final loc = ctx.pushOp(Call.make(offset.offset ?? -1), Call.length);
    if (offset.offset == null) {
      ctx.offsetTracker.setOffset(loc, offset);
    }
    ctx.pushOp(PushReturnValue.make(), PushReturnValue.LEN);
  } else {
    final dec0 = resolveStaticMethod(ctx, staticType, name);

    if (dec0.isBridge) {
      final bridge = dec0.bridge;
      final fnDescriptor = (bridge as BridgeConstructorDef).functionDescriptor;
      compileArgumentListWithBridge(ctx, e.argumentList, fnDescriptor);
    } else {
      final dec = dec0.declaration!;
      final fpl = (dec as ConstructorDeclaration).parameters.parameters;

      compileArgumentList(ctx, e.argumentList, staticType.file, fpl, dec,
          source: e);
    }

    if (dec0.isBridge) {
      final bridge = dec0.bridge!;
      if (bridge is BridgeClassDef && !bridge.wrap) {
        final type = TypeRef.fromBridgeTypeRef(ctx, bridge.type.type);

        final $null = BuiltinValue().push(ctx);
        final op = BridgeInstantiate.make($null.scopeFrameOffset,
            ctx.bridgeStaticFunctionIndices[type.file]!['${type.name}.']!);
        ctx.pushOp(op, BridgeInstantiate.len(op));
      } else {
        final op = InvokeExternal.make(ctx.bridgeStaticFunctionIndices[
            staticType.file]!['${staticType.name}.$name']!);
        ctx.pushOp(op, InvokeExternal.LEN);
        ctx.pushOp(PushReturnValue.make(), PushReturnValue.LEN);
      }
    } else {
      final offset = DeferredOrOffset.lookupStatic(
          ctx, staticType.file, staticType.name, name);
      final loc = ctx.pushOp(Call.make(offset.offset ?? -1), Call.length);
      if (offset.offset == null) {
        ctx.offsetTracker.setOffset(loc, offset);
      }
      ctx.pushOp(PushReturnValue.make(), PushReturnValue.LEN);
    }
  }

  return Variable.alloc(
      ctx, $resolved.concreteTypes.first.copyWith(boxed: true));
}
