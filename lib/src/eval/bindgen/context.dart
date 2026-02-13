import 'package:dart_eval/dart_eval_bridge.dart';

class BindgenContext {
  final String filename;
  final String uri;

  /// Eval file relative path used in registerXxx.add (e.g.
  /// `"src/bundle_context.eval.dart"`). When empty, falls back to
  /// `filename.replaceAll('.dart', '.eval.dart')`.
  final String registeredFile;

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

  BindgenContext(this.filename, this.uri,
      {required this.all,
      required this.bridgeDeclarations,
      required this.exportedLibMappings,
      this.registeredFile = ''});
}
