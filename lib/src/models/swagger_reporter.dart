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

