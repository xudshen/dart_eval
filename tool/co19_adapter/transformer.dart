// Validates co19 test source files for dart_eval compatibility.
//
// Used at generation time to check if a co19 source can be transformed.
// Actual source transformation happens at runtime in co19_runner.dart.

/// Regex matching co19 Expect import (various quote styles and path depths).
final _expectImportPattern =
    RegExp(r'''import\s+(['"])\.\.[\./]*Utils/expect\.dart\1\s*;''');

/// Regex matching co19 dynamic_check / static_type_helper imports.
final _utilImportPattern =
    RegExp(r'''import\s+(['"])\.\.[\./]*Utils/\w+\.dart\1\s*;''');

/// Regex matching any relative import (starts with . or ..).
final _relativeImportPattern =
    RegExp(r'''import\s+(['"])\.{1,2}/''');

/// Check if a co19 source file can be transformed for dart_eval.
///
/// Returns the transformed source, or `null` if the file has relative
/// imports that can't be handled (e.g., local lib.dart).
///
/// Note: This is only used at generation time for filtering.
/// The actual runtime transform is in co19_runner.dart.
String? transformSource(String source) {
  // Replace Expect import with package import.
  var result =
      source.replaceAll(_expectImportPattern, "import 'package:co19_expect/expect.dart';");

  // Remove dynamic_check / static_type_helper imports (not needed in dart_eval).
  result = result.replaceAll(_utilImportPattern, '// [co19_adapter] removed Utils import');

  // Check for remaining relative imports → can't transform.
  if (_relativeImportPattern.hasMatch(result)) {
    return null;
  }

  return result;
}
