# CLAUDE.md - AI Assistant Guide for dart_eval

## Project Overview

**dart_eval** is an extensible bytecode compiler and interpreter for the Dart language, written entirely in Dart. It enables dynamic code execution and code-push capabilities for AOT (Ahead-of-Time) compiled Dart applications.

- **Version**: 0.8.4
- **License**: BSD-3-Clause
- **Repository**: https://github.com/ethanblake4/dart_eval
- **Platform Support**: Android, iOS, Linux, macOS, Web, Windows
- **Related Packages**: `flutter_eval`, `eval_annotation`

## Quick Commands

```bash
# Install dependencies
dart pub get

# Run all tests
dart test

# Run a specific test file
dart test test/class_test.dart

# Analyze code for issues
dart analyze

# Format code (not enforced in CI, but recommended)
dart format .

# CLI commands (after installation)
dart_eval compile <source>  # Compile to EVC bytecode
dart_eval run <file.evc>    # Execute bytecode file
dart_eval dump <file.evc>   # Inspect bytecode contents

# Run performance benchmarks
dart run benchmark/performance_comparison.dart
```

## Architecture Overview

### Compilation Pipeline

```
Dart Source Code (String)
         ↓
    Analyzer (parseString)
         ↓
    AST (Abstract Syntax Tree)
         ↓
    Compiler Context Setup
         ↓
    Bytecode Generation (EVC format)
         ↓
    Program (metadata + bytecode)
         ↓
    Runtime Loading
         ↓
    Stack-based VM Execution
         ↓
    Result ($Value wrapped)
```

### Directory Structure

```
dart_eval/
├── lib/
│   ├── dart_eval.dart            # Main public API (eval, Compiler, Runtime, Program)
│   ├── dart_eval_bridge.dart     # Bridge/interop API
│   ├── dart_eval_security.dart   # Security/permissions API
│   ├── dart_eval_extensions.dart # Extensions API
│   ├── stdlib/                   # Public stdlib exports (core, async, collection, etc.)
│   └── src/eval/                 # Internal implementation
│       ├── compiler/             # Compilation system
│       ├── runtime/              # Virtual machine
│       ├── bridge/               # Interop system
│       ├── shared/               # Shared code (stdlib implementations)
│       ├── bindgen/              # Code generation for bindings
│       ├── cli/                  # CLI commands
│       └── utils/                # Utility functions
├── test/                         # Test suite (34+ test files, 330+ tests)
├── benchmark/                    # Performance benchmarks
├── example/                      # Usage examples
├── bin/                          # CLI entry point
└── .github/workflows/dart.yml    # CI configuration
```

## Key Source Directories

### `/lib/src/eval/compiler/` - Compilation System

The heart of dart_eval. Transforms Dart AST into EVC bytecode.

| Subdirectory | Purpose |
|--------------|---------|
| `expression/` | Compiles expressions (method_invocation.dart, binary.dart, identifier.dart, literal.dart) |
| `declaration/` | Compiles top-level declarations (class.dart, function.dart, field.dart, constructor.dart) |
| `statement/` | Compiles statements (if.dart, for.dart, while.dart, try.dart, switch.dart) |
| `collection/` | List/Map/Set compilation (list.dart, set_map.dart, spread.dart) |
| `helpers/` | Shared utilities (invoke.dart, closure.dart, tearoff.dart, equality.dart) |
| `macros/` | Reusable patterns (branch.dart for if/else logic) |
| `model/` | Data models (library.dart, source.dart) |
| `optimizer/` | Performance optimizations |

**Key files:**
- `compiler.dart` - Main Compiler class
- `context.dart` - CompilerContext managing compilation state
- `program.dart` - Program output with bytecode and metadata
- `scope.dart` - Variable scope management
- `type.dart` - Type system implementation
- `variable.dart` - Variable representation (21+ classes)

### `/lib/src/eval/runtime/` - Runtime VM

Executes compiled EVC bytecode using a stack-based virtual machine.

**Key files:**
- `runtime.dart` - Main Runtime class and VM executor
- `class.dart` - Runtime class representations
- `function.dart` - Function/closure representations
- `ops/all_ops.dart` - Complete bytecode operation catalog
- `ops/primitives.dart` - Arithmetic, comparisons, boxing/unboxing
- `ops/memory.dart` - Stack and variable operations
- `ops/flow.dart` - Control flow (jumps, branches, returns)
- `ops/objects.dart` - Property access, method calls

### `/lib/src/eval/bridge/` - Interop System

Enables communication between dart_eval code and native Dart.

- **Wrapper Interop**: Use native classes in eval code (cannot extend)
- **Bridge Interop**: Extend/implement native classes in eval code

**Key files:**
- `registry.dart` - Bridge declaration registry
- `runtime_bridge.dart` - Runtime bridge mechanism
- `declaration/class.dart` - Bridge class definitions
- `declaration/function.dart` - Bridge function definitions

### `/lib/src/eval/shared/stdlib/` - Standard Library

Bridge implementations for `dart:core`, `dart:async`, `dart:collection`, `dart:convert`, `dart:io`, `dart:math`, `dart:typed_data`.

## Naming Conventions

| Pattern | Purpose | Examples |
|---------|---------|----------|
| `$` prefix | Boxed value wrappers | `$String`, `$Map`, `$Value`, `$Closure` |
| `Eval` prefix | Runtime class representations | `EvalClass`, `EvalFunction` |
| `Bridge` prefix | Interop bridge classes | `BridgeClassDef`, `BridgeFunctionDeclaration` |
| `compile*` | Compilation functions | `compileBinaryExpression`, `compileExpression` |
| `OP_` prefix | Bytecode opcode constants | `OP_JMPC`, `OP_ADDVV`, `OP_INVOKE_DYNAMIC` |
| `.g.dart` suffix | Generated files | `class.g.dart`, `function.g.dart` |
| `*Plugin` | Plugin implementations | `DartCorePlugin`, `DartAsyncPlugin` |

## Testing Conventions

### Test Structure

```dart
void main() {
  group('Feature name', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Test case description', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              return 42;
            }
          '''
        }
      });

      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        42
      );
    });
  });
}
```

### Key Testing Patterns

1. Use `compiler.compileWriteAndLoad()` to compile and get runtime
2. Arguments must be wrapped in `$Value` types (except int, double, bool, List)
3. Tests are organized by feature in `group()` blocks
4. Run specific tests with `dart test test/feature_test.dart`

### Test Files by Category

| Category | Files |
|----------|-------|
| Language Features | `class_test.dart`, `function_test.dart`, `enum_test.dart`, `pattern_test.dart`, `records_test.dart` |
| Control Flow | `loop_test.dart`, `switch_test.dart`, `exception_test.dart` |
| Operations | `operator_test.dart`, `postfix_test.dart`, `prefix_test.dart`, `expression_test.dart` |
| Collections | `collection_test.dart`, `set_test.dart` |
| Standard Library | `stdlib_test.dart`, `string_test.dart`, `convert_test.dart`, `datetime_test.dart` |
| Async | `async_test.dart` |
| Interop | `bridge_test.dart`, `wrap_test.dart` |
| Performance | `performance_benchmark_test.dart` |

## Development Workflow

### Adding a New Feature

1. **Start with a test** - Write a failing test first (see CONTRIBUTING.md)
2. **Locate the right file** - Expression compilation goes in `compiler/expression/`, statements in `compiler/statement/`, etc.
3. **Follow existing patterns** - Look at similar features for structure
4. **Handle type information** - Update type tracking in `Variable` and `TypeRef`
5. **Run tests** - Ensure all existing tests pass

### Common Modification Points

- **New expression type**: Add to `compiler/expression/`, update expression dispatcher
- **New statement type**: Add to `compiler/statement/`, update statement dispatcher
- **New bytecode op**: Add to `runtime/ops/`, register in `all_ops.dart`
- **New stdlib bridge**: Add to `shared/stdlib/`, register plugin

### CI Pipeline

The GitHub Actions workflow (`.github/workflows/dart.yml`) runs on PRs to master:
1. `dart pub get` - Install dependencies
2. `dart analyze` - Static analysis
3. `dart test` - Run test suite

## Code Style

- Uses `package:lints/recommended.yaml` for analysis
- Standard Dart formatting conventions
- Doc comments on public APIs
- Complex algorithms should have inline explanations

## Important Types

### CompilerContext
Tracks compilation state: scopes, stack frames, bytecode ops list, type tracking, library references.

### Variable
Represents a variable during compilation:
```dart
class Variable {
  int scopeFrameOffset;  // Position in stack frame
  TypeRef type;          // Type information
  String? name;          // Variable name
  // Methods: boxIfNeeded(), push(), invoke(), etc.
}
```

### TypeRef / TypeSpec
- `TypeRef` - Type references during compilation
- `TypeSpec` - Type specification (library + name)
- Handles nullable types, generics, boxing/unboxing logic

### $Value / $Instance
Runtime boxed values that carry type information and enable interop.

## Language Feature Support

**Fully Supported**: Classes, inheritance, functions, async/await, collections (List, Map, Set), control flow, operators, try/catch

**Partially Supported**: Generics (classes partial), Records, Patterns, Null safety

**Not Yet Implemented**: Generators, Mixins, Extension methods, Typedefs

See the README for the complete feature support table.

## Security Model

The runtime supports fine-grained permissions:
- `FilesystemPermission` - File system access control
- `NetworkPermission` - Network/HTTP access
- `ProcessRunPermission` - Process execution

## Debugging Tips

1. **Compilation errors**: Check `CompileError` for file/library/AST offset info
2. **Runtime issues**: Enable diagnostic mode to trace execution
3. **Type mismatches**: Verify boxing/unboxing with `$value` property
4. **Test failures**: The error message often points to the missing implementation

## Performance

### Benchmarks

Run performance comparison benchmarks:
```bash
dart run benchmark/performance_comparison.dart
```

### Performance Characteristics

As an interpreter, dart_eval is slower than native AOT-compiled Dart. Typical performance ratios:

| Operation Type | vs Native Dart |
|----------------|----------------|
| Property access | ~12x slower |
| List operations | ~40x slower |
| Collection iteration | ~44x slower |
| Loop arithmetic | ~53x slower |
| Recursive calls | ~115x slower |
| Object methods | ~125x slower |

These ratios are expected for interpreter-based execution and acceptable for dynamic code scenarios.

### Key Optimizations Implemented

1. **Collection Boxing** (`ops/primitives.dart`): `BoxList`, `BoxMap`, `BoxSet` use type-checked wrapping instead of spread operators, yielding 35x improvement for list-heavy operations

2. **Argument Copying** (`ops/flow.dart`): `PushScope` unrolls argument copying for common cases (0-3 args)

3. **Equality Fast Path** (`ops/objects.dart`): `CheckEq` skips method lookup for primitive types

4. **Local Variable Caching**: Runtime property accesses cached in local variables to reduce overhead

See `PERFORMANCE_OPTIMIZATIONS.md` and `PERFORMANCE_RESULTS.md` for detailed analysis.

## Key Dependencies

- `analyzer: ^8.2.0` - Dart AST parsing (do not resolve, only parse)
- `dart_style: ^3.0.0` - Code formatting
- `directed_graph` - Dependency graph analysis
- `change_case` - String case conversion

## External Resources

- [pub.dev package](https://pub.dev/packages/dart_eval)
- [Web example (evalpad)](https://ethanblake.xyz/evalpad)
- [GitHub Sponsors](https://github.com/sponsors/ethanblake4)
