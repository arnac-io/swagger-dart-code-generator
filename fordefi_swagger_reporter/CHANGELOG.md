# Changelog

## 1.0.0 — 2026-05-20

- Initial release. Extracts `SwaggerReporter` interface and
  `SwaggerReporterHelper` static dispatcher from the fork's
  `lib/src/models/swagger_reporter.dart` into its own publishable package.
- No behavior change. Generated code that previously imported
  `package:swagger_dart_code_generator/src/models/swagger_reporter.dart` now
  imports `package:fordefi_swagger_reporter/fordefi_swagger_reporter.dart`.
