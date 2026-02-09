/// Programmatic CLI APIs for dart_eval compile/bind operations.
///
/// Use this library when you want to invoke dart_eval compilation or
/// binding generation from Dart code (e.g. in a custom CLI tool) without
/// spawning a subprocess.
library;

export 'src/eval/cli/compile.dart' show compile, CompileResult;
export 'src/eval/cli/bind.dart' show bind, BindResult;
export 'src/eval/cli/bindings.dart' show loadBindingsInto, defaultBindingPaths;
