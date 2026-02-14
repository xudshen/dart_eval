import 'package:dart_eval/dart_eval_bridge.dart';

import 'expect_bridge.dart';

/// EvalPlugin that makes `package:co19_expect/expect.dart` available
/// to dart_eval compiled code, providing the co19 `Expect` assertion class.
class Co19ExpectPlugin implements EvalPlugin {
  @override
  String get identifier => 'package:co19_expect';

  @override
  void configureForCompile(BridgeDeclarationRegistry registry) {
    registry.defineBridgeClass($Expect.$declaration);
  }

  @override
  void configureForRuntime(Runtime runtime) {
    $Expect.configureForRuntime(runtime);
  }
}
