import 'package:dart_eval/dart_eval_bridge.dart';

class BindgenContext {
  final String filename;
  final String uri;
  final Set<String> imports = {};
  final Set<String> knownTypes = {};
  final Set<String> unknownTypes = {};
  final bool all;
  final Map<String, String> libOverrides = {};
  bool implicitSupers = false;
  final Map<String, List<BridgeDeclaration>> bridgeDeclarations;
  final Map<String, String> exportedLibMappings;

  /// Members marked with @Bind(extern: true).
  /// These get compile-time declarations but no runtime binding.
  final Set<String> externMembers = {};

  /// Path prefix for .eval.dart output relative to lib/ (e.g. '_eval').
  /// When non-empty, cross-package eval imports include this prefix:
  /// `package:foo/src/bar.dart` → `package:foo/_eval/src/bar.eval.dart`
  final String evalOutputPrefix;

  BindgenContext(this.filename, this.uri,
      {required this.all,
      required this.bridgeDeclarations,
      required this.exportedLibMappings,
      this.evalOutputPrefix = ''});
}
