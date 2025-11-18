/// Interface for reporting messages during code generation.
/// 
/// Classes using the swagger code generator can provide an implementation
/// of this interface to receive reporting messages during the generation process.
abstract class SwaggerReporter {
  /// Report a message during code generation.
  /// 
  /// [msg] - The message to report.
  void report(String msg);
}

/// Static helper class for reporting, similar to FLog pattern.
/// 
/// Usage in generated code:
/// ```dart
/// SwaggerReporterHelper.report('Error message');
/// ```
/// 
/// On the client side, set the reporter implementation:
/// ```dart
/// SwaggerReporterHelper.setReporter(MyReporter());
/// ```
class SwaggerReporterHelper {
  static SwaggerReporter? _reporter;
  
  /// Set the reporter implementation.
  static void setReporter(SwaggerReporter? reporter) {
    _reporter = reporter;
  }
  
  /// Report a message using the configured reporter.
  /// This is a static method that can be called from anywhere in the generated code.
  static void report(String msg) {
    _reporter?.report(msg);
  }
}

