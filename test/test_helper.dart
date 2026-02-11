import 'package:dart_eval/dart_eval.dart';

/// Compile and execute a single-file Dart program, returning main()'s result.
Object? evalMain(String source, {String package = 'example'}) {
  final compiler = Compiler();
  final runtime = compiler.compileWriteAndLoad({
    package: {'main.dart': source}
  });
  return runtime.executeLib('package:$package/main.dart', 'main');
}

/// Compile and execute a specific function from a single-file Dart program.
Object? evalFunction(String source, String function,
    {String package = 'example'}) {
  final compiler = Compiler();
  final runtime = compiler.compileWriteAndLoad({
    package: {'main.dart': source}
  });
  return runtime.executeLib('package:$package/main.dart', function);
}

/// Compile a multi-file package and return the Runtime.
Runtime compilePackage(Map<String, String> files,
    {String package = 'example'}) {
  final compiler = Compiler();
  return compiler.compileWriteAndLoad({package: files});
}

/// Compile multiple packages and return the Runtime.
Runtime compilePackages(Map<String, Map<String, String>> packages) {
  final compiler = Compiler();
  return compiler.compileWriteAndLoad(packages);
}
