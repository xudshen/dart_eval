import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';
import 'package:dart_eval/src/eval/runtime/ops/all_ops.dart';

class OffsetTracker {
  OffsetTracker(this.context);

  final Map<int, DeferredOrOffset> _deferredOffsets = {};
  CompilerContext context;

  void setOffset(int location, DeferredOrOffset offset) {
    _deferredOffsets[location] = offset;
  }

  List<EvcOp> apply(List<EvcOp> source) {
    _deferredOffsets.forEach((pos, offset) {
      final op = source[pos];
      if (op is Call) {
        int resolvedOffset;

        // Just removing this for consistency for now
        /*if (offset.offset != null) {
          resolvedOffset = offset.offset!;
        } else*/
        if (offset.methodType == 2) {
          final positions =
              context.instanceDeclarationPositions[offset.file!];
          final classPositions = positions?[offset.className!];
          final methodPositions = classPositions?[2];
          final resolved = methodPositions?[offset.name!];
          if (resolved == null) {
            throw CompileError(
                'Cannot resolve deferred instance method '
                '${offset.className}.${offset.name} '
                '(file ${offset.file})');
          }
          resolvedOffset = resolved;
        } else {
          final positions =
              context.topLevelDeclarationPositions[offset.file!];
          final resolved = positions?[offset.name!];
          if (resolved == null) {
            throw CompileError(
                'Cannot resolve deferred call to '
                '${offset.name} (file ${offset.file})');
          }
          resolvedOffset = resolved;
        }
        final newOp = Call.make(resolvedOffset);
        source[pos] = newOp;
      } else if (op is PushObjectPropertyImpl) {
        final indices = context.instanceGetterIndices[offset.file!];
        final classIndices = indices?[offset.className!];
        final resolved = classIndices?[offset.name!];
        if (resolved == null) {
          throw CompileError(
              'Cannot resolve deferred property '
              '${offset.className}.${offset.name} '
              '(file ${offset.file})');
        }
        final newOp =
            PushObjectPropertyImpl.make(op.objectOffset, resolved);
        source[pos] = newOp;
      }
    });
    return source;
  }
}

/// An structure pointing to a function that may or may not have been generated already. If it hasn't, the exact program
/// offset will be resolved later by the [OffsetTracker]
class DeferredOrOffset {
  DeferredOrOffset(
      {this.offset,
      this.file,
      this.name,
      this.className,
      this.methodType,
      this.targetScopeFrameOffset})
      : assert(offset != null || name != null);

  final int? offset;
  final int? file;
  final String? className;
  final int? methodType;
  final String? name;
  final int? targetScopeFrameOffset;

  factory DeferredOrOffset.lookupStatic(
      CompilerContext ctx, int library, String parent, String name) {
    if (ctx.topLevelDeclarationPositions[library]
            ?.containsKey('$parent.$name') ??
        false) {
      return DeferredOrOffset(
          file: library,
          offset: ctx.topLevelDeclarationPositions[library]!['$parent.$name'],
          name: '$parent.$name');
    } else {
      return DeferredOrOffset(file: library, name: '$parent.$name');
    }
  }

  @override
  String toString() {
    return 'DeferredOrOffset{offset: $offset, file: $file, name: $name}';
  }

  @override
  bool operator ==(Object other) =>
      other is DeferredOrOffset &&
      other.offset == offset &&
      other.file == file &&
      other.className == className &&
      other.name == name;

  @override
  int get hashCode =>
      offset.hashCode ^ className.hashCode ^ file.hashCode ^ name.hashCode;
}
