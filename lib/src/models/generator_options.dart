import 'package:json_annotation/json_annotation.dart';

part 'generator_options.g2.dart';

@JsonSerializable(fieldRename: FieldRename.snake, anyMap: true)
class GeneratorOptions {
  /// Instantiate generator options.
  GeneratorOptions({
    this.withBaseUrl = true,
    this.addBasePathToRequests = false,
    this.withConverter = true,
    this.ignoreHeaders = false,
    this.separateModels = false,
    this.classesWithNullabeLists = const [],
    this.buildOnlyModels = false,
    this.defaultValuesMap = const <DefaultValueMap>[],
    this.defaultHeaderValuesMap = const <DefaultHeaderValueMap>[],
    this.responseOverrideValueMap = const <ResponseOverrideValueMap>[],
    required this.inputFolder,
    required this.outputFolder,
    this.enumsCaseSensitive = true,
    this.useRequiredAttributeForHeaders = true,
    this.usePathForRequestNames = true,
    this.includeIfNull,
    this.modelPostfix = '',
    this.customReturnType = '',
    this.includePaths = const [],
    this.importPaths = const [],
    this.excludePaths = const [],
    this.inputUrls = const [],
    this.nullableModels = const [],
    this.cutFromModelNames = '',
    this.additionalHeaders = const [],
    this.overrideEqualsAndHashcode = true,
    this.overrideToString = true,
    this.pageWidth,
    this.overridenModels = const [],
    this.generateToJsonFor = const [],
    this.multipartFileType = 'List<int>',
    this.urlencodedFileType = 'Map<String, String>',
    this.generateFirstSucceedResponse = true,
  });

  /// Build options from a JSON map.
  factory GeneratorOptions.fromJson(Map<String, dynamic> json) =>
      _$GeneratorOptionsFromJson(json);

  @JsonKey(defaultValue: true)
  final bool usePathForRequestNames;

  @JsonKey(defaultValue: true)
  final bool generateFirstSucceedResponse;

  @JsonKey(defaultValue: true)
  final bool withBaseUrl;

  @JsonKey(defaultValue: false)
  final bool addBasePathToRequests;

  @JsonKey(defaultValue: null)
  final int? pageWidth;

  @JsonKey(defaultValue: true)
  final bool overrideToString;

  @JsonKey(defaultValue: true)
  final bool overrideEqualsAndHashcode;

  @JsonKey(defaultValue: 'List<int>')
  final String multipartFileType;

  @JsonKey(defaultValue: 'Map<String, String>')
  final String urlencodedFileType;

  @JsonKey(defaultValue: true)
  final bool withConverter;

  @JsonKey(defaultValue: [])
  final List<OverridenModelsItem> overridenModels;

  @JsonKey(defaultValue: [])
  final List<String> generateToJsonFor;

  @JsonKey(defaultValue: [])
  final List<String> additionalHeaders;

  @JsonKey(defaultValue: [])
  List<InputUrl> inputUrls;

  @JsonKey(defaultValue: [])
  List<String> nullableModels;

  @JsonKey(defaultValue: false)
  final bool separateModels;

  @JsonKey(defaultValue: true)
  final bool useRequiredAttributeForHeaders;

  @JsonKey(defaultValue: false)
  final bool ignoreHeaders;

  @JsonKey(defaultValue: false)
  final bool enumsCaseSensitive;

  @JsonKey(defaultValue: null)
  final bool? includeIfNull;

  @JsonKey(defaultValue: '')
  final String inputFolder;

  @JsonKey(defaultValue: '')
  final String outputFolder;

  @JsonKey(defaultValue: [])
  final List<String> classesWithNullabeLists;

  @JsonKey(defaultValue: '')
  final String cutFromModelNames;

  @JsonKey(defaultValue: false)
  final bool buildOnlyModels;

  @JsonKey(defaultValue: '')
  final String modelPostfix;

  @JsonKey(defaultValue: <DefaultValueMap>[])
  final List<DefaultValueMap> defaultValuesMap;

  @JsonKey(defaultValue: <DefaultHeaderValueMap>[])
  final List<DefaultHeaderValueMap> defaultHeaderValuesMap;

  @JsonKey(defaultValue: <ResponseOverrideValueMap>[])
  final List<ResponseOverrideValueMap> responseOverrideValueMap;

  @JsonKey(defaultValue: [])
  final List<String> includePaths;

  @JsonKey(defaultValue: [])
  final List<String> importPaths;

  @JsonKey(defaultValue: '')
  final String customReturnType;

  @JsonKey(defaultValue: [])
  final List<String> excludePaths;

  /// Convert this options instance to JSON.
  Map<String, dynamic> toJson() => _$GeneratorOptionsToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class DefaultValueMap {
  DefaultValueMap({required this.typeName, required this.defaultValue});

  /// Build a default value map from a JSON map.
  factory DefaultValueMap.fromJson(Map<String, dynamic> json) =>
      _$DefaultValueMapFromJson(json);

  @JsonKey(defaultValue: '')
  final String typeName;

  @JsonKey(defaultValue: '')
  final String defaultValue;

  /// Convert this default value map instance to JSON.
  Map<String, dynamic> toJson() => _$DefaultValueMapToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class ResponseOverrideValueMap {
  ResponseOverrideValueMap(
      {required this.url, required this.method, required this.overriddenValue});

  /// Build a default value map from a JSON map.
  factory ResponseOverrideValueMap.fromJson(Map<String, dynamic> json) =>
      _$ResponseOverrideValueMapFromJson(json);

  @JsonKey(defaultValue: '')
  final String url;

  @JsonKey(defaultValue: '')
  final String method;

  @JsonKey(defaultValue: '')
  final String overriddenValue;

  /// Convert this default value map instance to JSON.
  Map<String, dynamic> toJson() => _$ResponseOverrideValueMapToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class DefaultHeaderValueMap {
  DefaultHeaderValueMap({required this.headerName, required this.defaultValue});

  @JsonKey(defaultValue: '')
  final String headerName;

  @JsonKey(defaultValue: '')
  final String defaultValue;

  Map<String, dynamic> toJson() => _$DefaultHeaderValueMapToJson(this);

  factory DefaultHeaderValueMap.fromJson(Map<String, dynamic> json) =>
      _$DefaultHeaderValueMapFromJson(json);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class InputUrl {
  InputUrl({
    required this.url,
    this.fileName,
  });

  @JsonKey()
  final String url;

  @JsonKey()
  final String? fileName;

  Map<String, dynamic> toJson() => _$InputUrlToJson(this);

  factory InputUrl.fromJson(Map<String, dynamic> json) =>
      _$InputUrlFromJson(json);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class OverridenModelsItem {
  @JsonKey()
  final String fileName;
  @JsonKey()
  final List<String> overridenModels;
  @JsonKey()
  final String importUrl;

  OverridenModelsItem({
    required this.fileName,
    required this.overridenModels,
    required this.importUrl,
  });

  Map<String, dynamic> toJson() => _$OverridenModelsItemToJson(this);

  factory OverridenModelsItem.fromJson(Map<String, dynamic> json) =>
      _$OverridenModelsItemFromJson(json);
}
