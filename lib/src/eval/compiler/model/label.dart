import 'package:dart_eval/src/eval/compiler/context.dart';

class CompilerLabel {
  final int offset;
  final int Function(CompilerContext ctx) cleanup;
  final int Function(CompilerContext ctx)? continueCleanup;
  final String? name;
  final LabelType type;

  const CompilerLabel(this.type, this.offset, this.cleanup,
      {this.name, this.continueCleanup});
}

class SimpleCompilerLabel implements CompilerLabel {
  @override
  get offset => -1;
  @override
  final String? name;
  @override
  get type => LabelType.block;
  @override
  get continueCleanup => null;

  const SimpleCompilerLabel({this.name});

  @override
  get cleanup => (CompilerContext ctx) {
        ctx.endAllocScopeQuiet();
        return -1;
      };
}

enum LabelType { loop, branch, block }
