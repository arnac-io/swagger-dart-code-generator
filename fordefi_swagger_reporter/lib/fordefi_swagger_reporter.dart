/// Runtime reporter abstraction for fordefi swagger-generated Dart clients.
///
/// The fordefi fork of `swagger_dart_code_generator` emits calls like
/// `SwaggerReporterHelper.report(...)` inside generated chopper clients and
/// model factories. This package provides those symbols so the generated
/// code is self-contained and can be published as a normal Pub package.
///
/// Consumers wire a concrete reporter at startup:
///
/// ```dart
/// SwaggerReporterHelper.setReporter(_FLogReporter());
///
/// class _FLogReporter implements SwaggerReporter {
///   @override
///   void report(String msg) => FLog.error(text: msg);
/// }
/// ```
library fordefi_swagger_reporter;

/// Interface for reporting messages from swagger-generated code.
///
/// Generated chopper clients and model factories call
/// [SwaggerReporterHelper.report] to surface generation errors at runtime.
/// Consumers implement this interface and register an instance via
/// [SwaggerReporterHelper.setReporter] to route those messages to their
/// logger of choice.
abstract class SwaggerReporter {
  /// Report a message from generated code.
  void report(String msg);
}

/// Static dispatcher used by generated code.
///
/// Generated code calls [report] from anywhere without holding a
/// reporter instance. Consumers register their reporter once at startup
/// via [setReporter]. Until a reporter is registered, calls are no-ops.
class SwaggerReporterHelper {
  static SwaggerReporter? _reporter;

  /// Register (or clear) the reporter implementation.
  ///
  /// Pass `null` to disable reporting. Safe to call multiple times.
  static void setReporter(SwaggerReporter? reporter) {
    _reporter = reporter;
  }

  /// Forward [msg] to the registered reporter, or no-op if none registered.
  static void report(String msg) {
    _reporter?.report(msg);
  }
}
