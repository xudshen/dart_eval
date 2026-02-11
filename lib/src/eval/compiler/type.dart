import 'package:analyzer/dart/ast/ast.dart';
import 'package:collection/collection.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/expression/method_invocation.dart';
import 'package:dart_eval/src/eval/compiler/model/function_type.dart';
import 'package:dart_eval/src/eval/runtime/type.dart';

import 'builtins.dart';
import 'context.dart';
import 'errors.dart';

part 'types/type_ref.dart';
part 'types/type_resolver.dart';
part 'types/return_type.dart';
