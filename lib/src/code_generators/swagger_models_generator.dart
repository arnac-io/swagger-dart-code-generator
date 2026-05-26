import 'package:collection/collection.dart';
import 'package:recase/recase.dart';
import 'package:swagger_dart_code_generator/src/code_generators/constants.dart';
import 'package:swagger_dart_code_generator/src/code_generators/enum_model.dart';
import 'package:swagger_dart_code_generator/src/code_generators/swagger_generator_base.dart';
import 'package:swagger_dart_code_generator/src/code_generators/swagger_requests_generator.dart';
import 'package:swagger_dart_code_generator/src/exception_words.dart';
import 'package:swagger_dart_code_generator/src/extensions/string_extension.dart';
import 'package:swagger_dart_code_generator/src/models/generator_options.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/responses/swagger_schema.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/swagger_root.dart';

abstract class SwaggerModelsGenerator extends SwaggerGeneratorBase {
  final GeneratorOptions _options;

  @override
  GeneratorOptions get options => _options;

  SwaggerModelsGenerator(this._options);

  /// Wrappers detected with `oneOf` + `discriminator.mapping` that should
  /// emit a `sealed class I<wrapperName>` interface alongside themselves.
  /// Populated by [_buildOneOfAnalysis] at the start of [generateBase].
  /// Key: PascalCase wrapper class name.
  Map<String, OneOfInterfaceInfo> _oneOfWrappers = {};

  /// Subtype classes (concrete types referenced from some wrapper's
  /// discriminator mapping) that need `implements I<wrapperName>` and
  /// null-override stubs for any missing common property.
  /// Key: PascalCase subtype class name.
  Map<String, List<OneOfSubtypeMembership>> _oneOfSubtypes = {};

  String generate({
    required SwaggerRoot root,
    required String fileName,
    required List<EnumModel> allEnums,
  });

  String getExtendsString(SwaggerSchema schema);

  List<String> getAllListEnumNames(SwaggerRoot root);

  String generateModelClassContent(
    SwaggerRoot root,
    String className,
    SwaggerSchema schema,
    Map<String, SwaggerSchema> schemas,
    List<DefaultValueMap> defaultValues,
    List<String> classesWithNullableLists,
    List<String> allEnumNames,
    List<String> allEnumListNames,
    Map<String, SwaggerSchema> allClasses,
    String fileName,
  ) {
    if (options.overridenModels
            .firstWhereOrNull((e) => e.fileName == fileName)
            ?.overridenModels
            .contains(getValidatedClassName(className)) ==
        true) {
      return '';
    }

    if (schema.isEnum) {
      return '';
    }

    if (schema.ref.isNotEmpty) {
      return '';
    }

    if (kBasicSwaggerTypes.contains(schema.type.toLowerCase())) {
      return '';
    }

    if (schema.isListEnum) {
      return '';
    }

    if (schema.hasRef) {
      return 'class $className {}';
    }

    if (schema.anyOf.isNotEmpty) {
      if (schema.type == kObject) {
        return 'typedef $className = Map<String, dynamic>;';
      } else {
        return 'typedef $className = Object;';
      }
    }

    if (schema.type == 'array') {
      final items = schema.items;

      if (items != null) {
        if (items.hasRef) {
          final ref = items.ref;

          final itemSchema =
              allClasses[getValidatedClassName(ref.getUnformattedRef())];

          if (itemSchema != null && kBasicTypes.contains(itemSchema.type)) {
            return 'typedef $className = List<${kBasicTypesMap[itemSchema.type]}>;';
          }

          final itemType = getValidatedClassName(ref.getUnformattedRef());
          return 'typedef $className = List<$itemType>;';
        }

        final itemsType = items.type;

        if (itemsType != kObject) {
          return 'typedef $className = List<Object>;';
        }

        if (kBasicTypes.contains(itemsType)) {
          return 'typedef $className = List<${kBasicTypesMap[itemsType]}>;';
        }

        final itemClassName = '$className\$Item';

        if (options.overridenModels
                .firstWhereOrNull((e) => e.fileName == fileName)
                ?.overridenModels
                .contains(getValidatedClassName(itemClassName)) ==
            true) {
          return '';
        }

        final resultClass = generateModelClassString(
          root,
          itemClassName,
          items,
          schemas,
          defaultValues,
          classesWithNullableLists,
          allEnumNames,
          allEnumListNames,
          allClasses,
        );

        return 'typedef $className = List<$itemClassName>; $resultClass';
      }

      return 'typedef $className = List<Object>;';
    }

    return generateModelClassString(
      root,
      className,
      schema,
      schemas,
      defaultValues,
      classesWithNullableLists,
      allEnumNames,
      allEnumListNames,
      allClasses,
    );
  }

  Map<String, SwaggerSchema> getClassesFromInnerClasses(
    Map<String, SwaggerSchema> classes,
  ) {
    final result = <String, SwaggerSchema>{};

    classes.forEach((classKey, schema) {
      final properties = {
        ...schema.properties,
        ...schema.items?.properties ?? {},
      };

      for (var element in schema.allOf) {
        properties.addAll(element.properties);

        if (element.ref.isNotEmpty) {
          final neededClass = classes[element.ref.getUnformattedRef()];
          properties.addAll(neededClass?.properties ?? {});
        }
      }

      final shouldUseItemsProperties =
          schema.items?.properties.isNotEmpty == true;

      properties.forEach((propertyKey, propSchema) {
        final itemPart = shouldUseItemsProperties ? '\$Item\$' : '\$';

        final innerClassName = getValidatedClassName(
            '${getValidatedClassName(classKey)}$itemPart${getValidatedClassName(propertyKey)}');

        if (propSchema.properties.isNotEmpty) {
          result[innerClassName] = propSchema;
        }

        final items = propSchema.items;

        if (items != null && items.properties.isNotEmpty) {
          propSchema.type = 'object';

          result['$innerClassName\$Item'] = items;
        }
      });

      if (schema.items != null) {
        result.addAll(getClassesFromInnerClasses(
            {'${getValidatedClassName(classKey)}\$item': schema.items!}));
      }
    });

    if (result.isNotEmpty) {
      result.addAll(getClassesFromInnerClasses(result));
    }

    return result;
  }

  Map<String, SwaggerSchema> getClassesFromResponses(SwaggerRoot root) {
    final results = <String, SwaggerSchema>{};

    final paths = root.paths;

    paths.forEach((key, path) {
      path.requests.forEach((operation, request) {
        if (!supportedRequestTypes.contains(operation.toLowerCase())) {
          return;
        }

        if (options.excludePaths.isNotEmpty &&
            options.excludePaths
                .any((exclPath) => RegExp(exclPath).hasMatch(operation))) {
          return;
        }

        if (options.includePaths.isNotEmpty &&
            !options.includePaths
                .any((inclPath) => RegExp(inclPath).hasMatch(operation))) {
          return;
        }
        final responses = request.responses;

        final neededResponse = responses['200'] ?? responses['201'];

        final neededSchema =
            neededResponse?.schema ?? neededResponse?.content?.schema;

        if (neededSchema != null &&
            neededSchema.type == kObject &&
            neededSchema.properties.isNotEmpty) {
          final pathText = key.split('/').map((e) => e.pascalCase).join();
          final requestText = operation.pascalCase;

          results['$pathText$requestText\$Response'] = neededSchema;
        } else if (neededSchema != null &&
            neededSchema.title.isNotEmpty &&
            neededSchema.allOf.isNotEmpty) {
          final properties = <String, SwaggerSchema>{};

          for (final allOf in neededSchema.allOf) {
            properties.addAll(allOf.properties);

            if (allOf.ref.isNotEmpty) {
              final schema = root.allSchemas[allOf.ref.getUnformattedRef()];
              properties.addAll(schema?.properties ?? {});
            }
          }

          results[neededSchema.title] = SwaggerSchema(properties: properties);
        } else if (neededSchema?.type == kArray) {
          final itemsSchema = neededSchema?.items;

          if (itemsSchema?.properties.isNotEmpty == true) {
            final pathText = key.split('/').map((e) => e.pascalCase).join();
            final requestText = operation.pascalCase;
            results['$pathText$requestText\$Response'] = neededSchema!;
          }
        }
      });
    });

    return results;
  }

  String generateBase({
    required SwaggerRoot root,
    required String fileName,
    required Map<String, SwaggerSchema> classes,
    required List<EnumModel> allEnums,
    required bool generateEnumsMethods,
  }) {
    final converters = generateJsonConverters();
    final allEnumsString = generateEnumsMethods
        ? allEnums
            .map((e) => e.generateFromJsonToJson(options.enumsCaseSensitive))
            .join()
        : '';

    final allEnumListNames = getAllListEnumNames(root);

    final classesFromResponses = getClassesFromResponses(root);
    classes.addAll(classesFromResponses);

    final classesFromInnerClasses = getClassesFromInnerClasses(classes);

    classes.addAll(classesFromInnerClasses);

    if (classes.isEmpty) {
      return allEnumsString;
    }

    // Analyze `oneOf` + `discriminator` wrappers up front so
    // generateModelClassString can decorate wrapper/subtype emissions.
    _buildOneOfAnalysis(classes);

    var results = classes.keys.map((String className) {
      if (classes['enum'] != null) {
        return '';
      }

      final currentClass = classes[className]!;

      return generateModelClassContent(
        root,
        className.pascalCase,
        currentClass,
        classes,
        options.defaultValuesMap,
        options.classesWithNullabeLists,
        allEnums.map((e) => e.name).toList(),
        allEnumListNames,
        classes,
        fileName,
      );
    }).join('\n');

    final listEnums = getAllListEnumNames(root);

    for (var listEnum in listEnums) {
      results = results.replaceAll(' $listEnum ', ' List<$listEnum> ');
    }

    return converters + results + allEnumsString;
  }

  static String getValidatedParameterName(String parameterName) {
    if (parameterName.isEmpty) {
      return parameterName;
    }

    final isEnum = parameterName.startsWith('enums.');

    if (isEnum) {
      parameterName = parameterName.substring(6);
    }

    final words = parameterName.split('\$');

    final result = words
        .map((e) => e
            .split(RegExp(r'\W+|\_'))
            .mapIndexed(
                (int index, String str) => index == 0 ? str : str.capitalize)
            .join())
        .join('\$');

    if (isEnum) {
      return 'enums.$result';
    }

    if (exceptionWords.contains(result.camelCase) ||
        kBasicTypes.contains(result.camelCase)) {
      return '\$$result';
    }

    if (result.isEmpty) {
      return kUndefinedParameter;
    }

    return result.camelCase;
  }

  String getParameterTypeName(
    String className,
    String parameterName,
    SwaggerSchema? parameter,
    String modelPostfix,
    String? refNameParameter,
  ) {
    if (refNameParameter != null) {
      return refNameParameter.pascalCase;
    }

    if (parameter == null) return 'Object';

    if (parameter.properties.isNotEmpty) {
      return getValidatedClassName(
          '${getValidatedClassName(className)}\$${getValidatedClassName(parameterName)}$modelPostfix');
    }

    if (parameter.items?.properties.isNotEmpty == true) {
      final parameterNameCombination =
          '${getValidatedClassName(className)}\$${getValidatedClassName(parameterName)}\$Item$modelPostfix';
      return 'List<${getValidatedClassName(parameterNameCombination)}>';
    }

    if (parameter.hasRef) {
      return parameter.ref.split('/').last.pascalCase;
    }

    switch (parameter.type) {
      case 'integer':
      case 'int':
      case 'int32':
      case 'int64':
        return 'int';
      case 'boolean':
        return 'bool';
      case 'string':
        final scalar = options.scalars[parameter.format];
        if (scalar != null) {
          return scalar.type;
        } else if (parameter.format == 'date-time' ||
            parameter.format == 'date') {
          return 'DateTime';
        } else if (parameter.isEnum) {
          return 'enums.${getValidatedClassName(generateEnumName(getValidatedClassName(className), parameterName))}';
        }
        return 'String';
      case 'Date':
        return 'DateTime';
      case 'number':
        return 'double';
      case 'object':
        return 'Object';
      case 'array':
        final items = parameter.items;
        final typeName = getParameterTypeName(
            className, parameterName, items, modelPostfix, null);
        return 'List<$typeName>';
      default:
        return 'Object';
    }
  }

  String generateDefaultValueFromMap(DefaultValueMap map) {
    switch (map.typeName) {
      case 'int':
      case 'double':
      case 'bool':
        return map.defaultValue;
      default:
        return "'${map.defaultValue}'";
    }
  }

  String generateIncludeIfNullString() {
    if (options.includeIfNull == null) {
      return '';
    }

    return ', includeIfNull: ${options.includeIfNull}';
  }

  String generatePropertyJsonConverterAnnotation(SwaggerSchema schema) {
    final override =
        schema.type == 'string' ? options.scalars[schema.format] : null;
    if (override == null) {
      return '';
    }

    return '@_\$${schema.format.pascalCase}JsonConverter()';
  }

  String generateJsonConverters() {
    if (options.scalars.isEmpty) {
      return '';
    }

    var result = '';

    for (final MapEntry(:key, :value) in options.scalars.entries) {
      final className = '_\$${key.pascalCase}JsonConverter';

      result += '''
class $className implements json.JsonConverter<${value.type}, String> {
  const $className();

  @override
  fromJson(json) => ${value.deserialize}(json);

  @override
  toJson(json) => ${value.serialize.isEmpty ? 'json.toString()' : '${value.serialize}(json)'};
}
''';
    }

    return result;
  }

  String generatePropertyContentByDefault({
    required SwaggerSchema prop,
    required String propertyName,
    required String propertyKey,
    required List<String> allEnumNames,
    required List<String> allEnumListNames,
    required List<String> requiredProperties,
    required bool isDeprecated,
  }) {
    var typeName = '';

    if (prop.hasOriginalRef) {
      typeName = getValidatedClassName(prop.originalRef);
    }

    if (typeName.isEmpty) {
      typeName = kDynamic;
    }

    propertyKey = propertyKey.replaceAll('\$', '\\\$');

    final unknownEnumValue = generateEnumValue(
      allEnumNames: allEnumNames,
      allEnumListNames: allEnumListNames,
      propertyName: propertyName,
      typeName: typeName.toString(),
      defaultValue: prop.defaultValue,
      isList: false,
      isNullable: isNullable(typeName, [], propertyKey, prop),
    );

    final dateToJsonValue = generateToJsonForDate(prop);

    final includeIfNullString = generateIncludeIfNullString();
    bool isNullableProperty = false;

    if (typeName != kDynamic &&
        (prop.shouldBeNullable || options.nullableModels.contains(typeName))) {
      typeName = typeName.makeNullable();
      isNullableProperty = true;
    }

    if (requiredProperties.isNotEmpty &&
        !requiredProperties.contains(propertyKey)) {
      typeName = typeName.makeNullable();
      isNullableProperty = true;
    }

    if (requiredProperties.isNotEmpty &&
        !requiredProperties.contains(propertyKey)) {
      typeName = typeName.makeNullable();
      isNullableProperty = true;
    }

    if (isNullableProperty && options.ignoredKeys.contains(propertyKey)) {
      return '';
    }

    final jsonKeyContent =
        "@JsonKey(name: '$propertyKey'$includeIfNullString$dateToJsonValue${unknownEnumValue.jsonKey})\n";
    final deprecatedContent = isDeprecated ? '@deprecated\n' : '';

    return '\t$jsonKeyContent$deprecatedContent\t $typeName ${generateFieldName(propertyName)};${unknownEnumValue.fromJson}';
  }

  JsonEnumValue generateEnumValue({
    required List<String> allEnumNames,
    required List<String> allEnumListNames,
    required String propertyName,
    required String typeName,
    required dynamic defaultValue,
    required bool isList,
    required bool isNullable,
    String className = '',
  }) {
    final validatedTypeName = getValidatedClassName(typeName);

    var jsonKey = '';
    var fromJson = '';
    if (validatedTypeName.startsWith('enums.')) {
      isList = isList || allEnumListNames.contains(validatedTypeName);

      final enumNameCamelCase = typeName.replaceAll('enums.', '').camelCase;
      final propertyNameCamelCase = propertyName.pascalCase;
      final fromJsonPrefix = defaultValue == null
          ? enumNameCamelCase
          : '$enumNameCamelCase$propertyNameCamelCase';
      final String fromJsonSuffix;
      final String toJsonSuffix;

      var defaultValueSuffix = '';

      if (isList && options.classesWithNullabeLists.contains(className)) {
        defaultValueSuffix = 'defaultValue: null,';
      }

      if (isList) {
        fromJsonSuffix =
            options.classesWithNullabeLists.contains(className) && isList
                ? 'NullableListFromJson'
                : 'ListFromJson';
        toJsonSuffix = 'ListToJson';
      } else {
        fromJsonSuffix = isNullable ? 'NullableFromJson' : 'FromJson';
        toJsonSuffix = 'ToJson';
      }
      final fromJsonFunction = '$fromJsonPrefix$fromJsonSuffix';
      jsonKey =
          ', toJson: $enumNameCamelCase${isNullable && !isList ? 'Nullable$toJsonSuffix' : toJsonSuffix}, fromJson: $fromJsonFunction, $defaultValueSuffix';

      if (defaultValue != null) {
        var returnType = '';
        final String valueType;
        final String defaultValueString;
        if (isList && defaultValue is List) {
          valueType = 'List';
          returnType = 'List<$validatedTypeName>';
          final defaultValues = defaultValue
              .map((e) => '$validatedTypeName.${e.toString().camelCase}')
              .join(', ');
          defaultValueString = '[$defaultValues]';
        } else {
          valueType = 'Object';
          returnType = validatedTypeName;
          final defaultValueCamelCase = EnumModel.getValidatedEnumFieldName(
            defaultValue?.toString() ?? '',
            defaultValue?.toString() ?? '',
            false,
            [],
          );

          defaultValueString =
              '$validatedTypeName.${defaultValueCamelCase.substring(0, defaultValueCamelCase.indexOf('('))}';
        }

        if ((options.classesWithNullabeLists.contains(className) && isList) ||
            isNullable) {
          returnType = '$returnType?';
        }

        fromJson = '''

static $returnType $fromJsonFunction($valueType? value) => $enumNameCamelCase$fromJsonSuffix(value, $defaultValueString);
            ''';
      }
    }

    return JsonEnumValue(
      jsonKey: jsonKey,
      fromJson: fromJson,
    );
  }

  String generateToJsonForDate(SwaggerSchema map) {
    final type = map.type.toLowerCase();
    final format = map.format.toLowerCase();

    final isDate = type == kString && format == 'date';

    if (isDate) {
      return ', toJson: _dateToJson';
    }

    return '';
  }

  bool isNullable(
    String className,
    Iterable<String> requiredProperties,
    String propertyKey,
    SwaggerSchema prop,
  ) {
    return prop.shouldBeNullable ||
        options.nullableModels.contains(className) ||
        !requiredProperties.contains(propertyKey);
  }

  String nullable(
    String typeName,
    String className,
    Iterable<String> requiredProperties,
    String propertyKey,
    SwaggerSchema prop,
  ) {
    if (typeName.isEmpty) {
      return kObject.pascalCase.makeNullable();
    }

    if (isNullable(className, requiredProperties, propertyKey, prop)) {
      return typeName.makeNullable();
    }
    return typeName;
  }

  String generatePropertyContentBySchema(
    SwaggerSchema prop,
    String propertyName,
    String propertyKey,
    String className,
    List<String> allEnumNames,
    List<String> allEnumListNames,
    Map<String, String> basicTypesMap,
    List<String> requiredProperties,
  ) {
    final propertySchema = prop.schema!;
    var parameterName = propertySchema.ref.split('/').last;

    String typeName;
    if (basicTypesMap.containsKey(parameterName)) {
      typeName = basicTypesMap[parameterName]!;
    } else {
      typeName = getValidatedClassName(getParameterTypeName(
          className, propertyName, prop, options.modelPostfix, parameterName));
    }

    final includeIfNullString = generateIncludeIfNullString();

    final allEnumsNamesWithoutPrefix =
        allEnumNames.map((e) => e.replaceFirst('enums.', '')).toList();

    if (allEnumsNamesWithoutPrefix.contains(typeName)) {
      typeName = 'enums.$typeName';
    } else {
      typeName += options.modelPostfix;
    }

    final unknownEnumValue = generateEnumValue(
      allEnumNames: allEnumNames,
      allEnumListNames: allEnumListNames,
      propertyName: propertyName,
      typeName: typeName,
      defaultValue: prop.defaultValue,
      isList: false,
      isNullable: isNullable(className, requiredProperties, propertyKey, prop),
    );

    final dateToJsonValue = generateToJsonForDate(prop);

    final jsonKeyContent =
        "@JsonKey(name: '${_validatePropertyKey(propertyKey)}'$includeIfNullString${unknownEnumValue.jsonKey}$dateToJsonValue)\n";
    final deprecatedContent =
        propertySchema.deprecated ? kDeprecatedAnnotation : '';
    bool isNullableProperty = false;
    if (prop.shouldBeNullable ||
        (options.nullableModels.contains(className) &&
            !requiredProperties.contains(propertyKey))) {
      typeName = typeName.makeNullable();
      isNullableProperty = true;
    }
    if (isNullableProperty && options.ignoredKeys.contains(propertyKey)) {
      return '';
    }
    return '\t$jsonKeyContent$deprecatedContent\t$typeName ${generateFieldName(propertyName)};${unknownEnumValue.fromJson}';
  }

  String _validatePropertyKey(String key) {
    return key.replaceAll('\$', '\\\$');
  }

  String generatePropertyContentByAllOf({
    required SwaggerSchema prop,
    required String propertyKey,
    required String className,
    required List<String> allEnumNames,
    required List<String> allEnumListNames,
    required String propertyName,
    required List<String> requiredProperties,
    required Map<String, String> basicTypesMap,
  }) {
    final allOf = prop.allOf;
    String typeName;

    if (allOf
            .where((element) =>
                element.ref.isNotEmpty || element.properties.isNotEmpty)
            .length >
        1) {
      typeName = kDynamic;
    } else if (allOf.first.ref.isNotEmpty) {
      var className = allOf.first.ref.getRef();

      if (allEnumNames.contains(className)) {
        className = 'enums.$className';
      }

      typeName = getValidatedClassName(className);
    } else if (allOf.first.type.isNotEmpty &&
        kBasicTypesMap.containsKey(allOf.first.type)) {
      typeName = kBasicTypesMap[allOf.first.type]!;
    } else {
      typeName = kDynamic;
    }

    if (basicTypesMap.containsKey(typeName)) {
      typeName = basicTypesMap[typeName]!;
    }

    final includeIfNullString = generateIncludeIfNullString();

    final unknownEnumValue = generateEnumValue(
      allEnumNames: allEnumNames,
      allEnumListNames: allEnumListNames,
      propertyName: propertyName,
      typeName: typeName,
      defaultValue: prop.defaultValue,
      isList: false,
      className: className,
      isNullable: isNullable(className, requiredProperties, propertyKey, prop),
    );

    final jsonKeyContent =
        "@JsonKey(name: '${_validatePropertyKey(propertyKey)}'$includeIfNullString${unknownEnumValue.jsonKey})\n";

    final deprecatedContent = prop.deprecated ? kDeprecatedAnnotation : '';
    bool isNullableProperty = false;
    if (prop.shouldBeNullable ||
        options.nullableModels.contains(className) ||
        !requiredProperties.contains(propertyKey)) {
      typeName = typeName.makeNullable();
      isNullableProperty = true;
    }
    if (isNullableProperty && options.ignoredKeys.contains(propertyKey)) {
      return '';
    }
    return '\t$jsonKeyContent$deprecatedContent\t$typeName $propertyName;${unknownEnumValue.fromJson}';
  }

  String generatePropertyContentByRef(
    SwaggerSchema prop,
    String propertyName,
    String propertyKey,
    String className,
    List<String> allEnumNames,
    List<String> allEnumListNames,
    Map<String, String> basicTypesMap,
    List<String> requiredProperties,
    Map<String, SwaggerSchema> allClasses,
  ) {
    final parameterName = prop.ref.split('/').last;

    String typeName;
    final refSchema = allClasses[getValidatedClassName(parameterName)];
    if (kBasicSwaggerTypes.contains(refSchema?.type) &&
        allClasses[getValidatedClassName(parameterName)]?.isEnum != true) {
      if (refSchema?.format == 'datetime') {
        typeName = 'DateTime';
      } else {
        typeName = kBasicTypesMap[refSchema?.type]!;
      }
    } else if (basicTypesMap.containsKey(parameterName)) {
      typeName = basicTypesMap[parameterName]!;
    } else {
      typeName = getValidatedClassName(getParameterTypeName(
          className, propertyName, prop, options.modelPostfix, parameterName));

      typeName = getValidatedClassName(typeName);
    }

    if (allEnumNames.contains(typeName)) {
      typeName = 'enums.$typeName';
    } else if (!basicTypesMap.containsKey(parameterName) &&
        !allEnumListNames.contains(typeName)) {
      typeName += options.modelPostfix;
    }

    final isPropertyNullable = prop.shouldBeNullable ||
        options.nullableModels.contains(className) ||
        refSchema?.shouldBeNullable == true ||
        !requiredProperties.contains(propertyKey);

    final unknownEnumValue = generateEnumValue(
      allEnumNames: allEnumNames,
      allEnumListNames: allEnumListNames,
      propertyName: propertyName,
      typeName: typeName,
      defaultValue: prop.defaultValue,
      className: className,
      isList: false,
      isNullable: isPropertyNullable,
    );

    if (allEnumListNames.contains(typeName)) {
      typeName = 'List<$typeName>';
    }

    final includeIfNullString = generateIncludeIfNullString();

    final jsonKeyContent =
        "@JsonKey(name: '${_validatePropertyKey(propertyKey)}'$includeIfNullString${unknownEnumValue.jsonKey})\n";

    final deprecatedContent =
        refSchema?.deprecated == true ? kDeprecatedAnnotation : '';

    if (prop.shouldBeNullable ||
        options.nullableModels.contains(className) ||
        !requiredProperties.contains(propertyKey)) {
      typeName = typeName.makeNullable();
    }

    final propertySchema = allClasses[prop.ref.getUnformattedRef()];
    bool isNullableProperty = false;
    if (propertySchema?.shouldBeNullable == true ||
        isPropertyNullable ||
        options.nullableModels.contains(className)) {
      typeName = typeName.makeNullable();
      isNullableProperty = true;
    }

    if (options.classesWithNullabeLists.contains(className) &&
        typeName.startsWith('List<') &&
        !typeName.endsWith('?')) {
      typeName += '?';
    }

    if (isNullableProperty && options.ignoredKeys.contains(propertyKey)) {
      return '';
    }

    return '\t$jsonKeyContent$deprecatedContent\t$typeName $propertyName;${unknownEnumValue.fromJson}';
  }

  String generateEnumPropertyContent({
    required String key,
    required String className,
    required String propertyKey,
    required List<String> allEnumNames,
    required List<String> allEnumListNames,
    required SwaggerSchema prop,
    required List<String> requiredProperties,
    required bool isDeprecated,
  }) {
    final enumName = getValidatedClassName(generateEnumName(className, key));

    allEnumNames.add(enumName);

    final unknownEnumValue = generateEnumValue(
      allEnumNames: allEnumNames,
      allEnumListNames: allEnumListNames,
      propertyName: key,
      typeName: enumName,
      defaultValue: prop.defaultValue,
      isList: false,
      isNullable: isNullable(className, requiredProperties, propertyKey, prop),
    );

    final includeIfNullString = generateIncludeIfNullString();

    var enumPropertyName = className.capitalize + key.capitalize;

    if ((prop.shouldBeNullable || options.nullableModels.contains(className)) &&
        !requiredProperties.contains(propertyKey)) {
      enumPropertyName = enumPropertyName.makeNullable();
    }

    return '''
  @JsonKey(${unknownEnumValue.jsonKey.substring(2)}$includeIfNullString)
  ${isDeprecated ? kDeprecatedAnnotation : ''}
  $enumPropertyName ${generateFieldName(key)};

  ${unknownEnumValue.fromJson}''';
  }

  String _generateListPropertyTypeName({
    required List<String> allEnumNames,
    required List<String> allEnumListNames,
    required SwaggerSchema prop,
    required Map<String, String> basicTypesMap,
    required String propertyName,
    required String className,
    required Map<String, SwaggerSchema> allClasses,
  }) {
    if (className.endsWith('\$Item')) {
      return kObject.pascalCase;
    }

    final items = prop.items;

    var typeName = '';
    if (items != null) {
      typeName = getValidatedClassName(items.originalRef);

      if (typeName.isNotEmpty &&
          !kBasicTypes.contains(typeName.toLowerCase())) {
        typeName += options.modelPostfix;
      }

      if (typeName.isEmpty) {
        if (items.hasRef) {
          typeName = items.ref.split('/').last;

          if (!allEnumListNames.contains(typeName) &&
              !allEnumNames.contains(typeName) &&
              !basicTypesMap.containsKey(typeName)) {
            typeName += options.modelPostfix;
          }
        }

        if (basicTypesMap.containsKey(typeName)) {
          typeName = basicTypesMap[typeName]!;
        } else if (typeName.isNotEmpty && typeName != kDynamic) {
          typeName = typeName.pascalCase;
        }
      } else if (!allEnumNames.contains(typeName) &&
          !kBasicTypes.contains(typeName.toLowerCase())) {
        typeName = kBasicTypesMap[typeName] ?? typeName + options.modelPostfix;
      }

      if (typeName.isNotEmpty) {
        typeName = getValidatedClassName(typeName);
      }

      if (typeName.isEmpty) {
        if (items.type == 'array' || items.items != null) {
          return _generateListPropertyTypeName(
            allEnumListNames: allEnumListNames,
            allEnumNames: allEnumNames,
            basicTypesMap: basicTypesMap,
            className: className,
            allClasses: allClasses,
            prop: items,
            propertyName: propertyName,
          ).makeNullable().asList();
        }
      }

      if (allEnumNames.contains(typeName)) {
        typeName = 'enums.$typeName';
      }
    }

    if (typeName.isEmpty) {
      typeName = getParameterTypeName(
        className,
        propertyName,
        items,
        options.modelPostfix,
        null,
      );
    }

    if (items?.properties.isNotEmpty == true) {
      typeName += '\$Item';
    }

    return typeName;
  }

  String generateListPropertyContent({
    required String propertyName,
    required String propertyKey,
    required String className,
    required SwaggerSchema prop,
    required List<String> classesWithNullableLists,
    required List<String> allEnumNames,
    required List<String> allEnumListNames,
    required Map<String, String> basicTypesMap,
    required List<String> requiredProperties,
    required Map<String, SwaggerSchema> allClasses,
    required bool isDeprecated,
  }) {
    final jsonConverterAnnotation = prop.items == null
        ? ''
        : generatePropertyJsonConverterAnnotation(prop.items!);
    final typeName = _generateListPropertyTypeName(
      allEnumListNames: allEnumListNames,
      allEnumNames: allEnumNames,
      basicTypesMap: basicTypesMap,
      className: className,
      allClasses: allClasses,
      prop: prop,
      propertyName: propertyName,
    );

    final unknownEnumValue = generateEnumValue(
      allEnumNames: allEnumNames,
      allEnumListNames: allEnumListNames,
      className: className,
      propertyName: propertyName,
      typeName: typeName,
      defaultValue: prop.defaultValue,
      isList: true,
      isNullable: false,
    );

    final includeIfNullString = generateIncludeIfNullString();
    final validatedPropertyKey = _validatePropertyKey(propertyKey);

    String jsonKeyContent;
    if (unknownEnumValue.jsonKey.isEmpty) {
      if (options.classesWithNullabeLists
          .any((element) => RegExp(element).hasMatch(className))) {
        jsonKeyContent =
            "@JsonKey(name: '$validatedPropertyKey'$includeIfNullString)\n";
      } else {
        jsonKeyContent =
            "@JsonKey(name: '$validatedPropertyKey'$includeIfNullString, defaultValue: <$typeName>[])\n";
      }
    } else {
      jsonKeyContent =
          "@JsonKey(name: '$validatedPropertyKey'$includeIfNullString${unknownEnumValue.jsonKey})\n";
    }

    final deprecatedContent = isDeprecated ? kDeprecatedAnnotation : '';

    var listPropertyName = 'List<$typeName>';

    if (prop.shouldBeNullable ||
        options.nullableModels.contains(className) ||
        !requiredProperties.contains(propertyKey)) {
      listPropertyName = listPropertyName.makeNullable();
    }
    return '$jsonConverterAnnotation$jsonKeyContent$deprecatedContent $listPropertyName ${generateFieldName(propertyName)};${unknownEnumValue.fromJson}';
  }

  String generateGeneralPropertyContent({
    required String propertyName,
    required String propertyKey,
    required String className,
    required List<DefaultValueMap> defaultValues,
    required SwaggerSchema prop,
    required List<String> allEnumNames,
    required List<String> allEnumListNames,
    required List<String> requiredProperties,
    required bool isDeprecated,
  }) {
    final includeIfNullString = generateIncludeIfNullString();
    final jsonConverterAnnotation =
        generatePropertyJsonConverterAnnotation(prop);

    var jsonKeyContent =
        "@JsonKey(name: '${_validatePropertyKey(propertyKey)}'$includeIfNullString";

    final isDeprecatedContent = isDeprecated ? kDeprecatedAnnotation : '';

    var typeName = '';

    if (prop.hasAdditionalProperties && prop.type == 'object') {
      // Check if additionalProperties has a specific schema (not just true/false)
      // Exclude enum types from additionalPropertiesSchema
      if (prop.additionalPropertiesSchema != null &&
          !prop.additionalPropertiesSchema!.isEnum) {
        var valueTypeName = getParameterTypeName(
          className,
          propertyKey,
          prop.additionalPropertiesSchema,
          options.modelPostfix,
          null,
        );
        // Double-check that the resolved type name is not an enum
        if (!allEnumNames.contains(valueTypeName)) {
          typeName = 'Map<String, $valueTypeName>';
        } else {
          typeName = kMapStringDynamic;
        }
      } else {
        typeName = kMapStringDynamic;
      }
    } else if (prop.hasRef) {
      typeName = prop.ref.split('/').last.pascalCase + options.modelPostfix;
    } else {
      typeName = getParameterTypeName(
        className,
        propertyKey,
        prop,
        options.modelPostfix,
        null,
      );
    }

    if (allEnumNames.contains(typeName)) {
      typeName = 'enums.$typeName';
    }

    final unknownEnumValue = generateEnumValue(
      allEnumNames: allEnumNames,
      allEnumListNames: allEnumListNames,
      propertyName: propertyName,
      typeName: typeName,
      defaultValue: prop.defaultValue,
      isList: false,
      isNullable: isNullable(className, requiredProperties, propertyKey, prop),
      className: className,
    );

    final dateToJsonValue = generateToJsonForDate(prop);

    jsonKeyContent += unknownEnumValue.jsonKey;
    jsonKeyContent += dateToJsonValue;

    if ((prop.type == 'bool' || prop.type == 'boolean') &&
        prop.defaultValue != null) {
      jsonKeyContent += ', defaultValue: ${prop.defaultValue})\n';
    } else if (defaultValues
        .any((DefaultValueMap element) => element.typeName == typeName)) {
      final defaultValue = defaultValues.firstWhere(
          (DefaultValueMap element) => element.typeName == typeName);
      jsonKeyContent +=
          ', defaultValue: ${generateDefaultValueFromMap(defaultValue)})\n';
    } else {
      jsonKeyContent += ')\n';
    }
    bool isNullableProperty = false;
    if (prop.shouldBeNullable ||
        options.nullableModels.contains(className) ||
        !requiredProperties.contains(propertyKey)) {
      typeName = typeName.makeNullable();
      isNullableProperty = true;
    }
    if (isNullableProperty && options.ignoredKeys.contains(propertyKey)) {
      return '';
    }

    return '\t$jsonConverterAnnotation$jsonKeyContent$isDeprecatedContent $typeName $propertyName;${unknownEnumValue.fromJson}';
  }

  String generatePropertyContentByType(
    SwaggerSchema prop,
    String propertyName,
    String propertyKey,
    String className,
    List<DefaultValueMap> defaultValues,
    List<String> classesWithNullableLists,
    List<String> allEnumsNames,
    List<String> allEnumListNames,
    Map<String, String> basicTypesMap,
    List<String> requiredProperties,
    Map<String, SwaggerSchema> allClasses,
    bool isDeprecated,
  ) {
    switch (prop.type) {
      case 'array':
        return generateListPropertyContent(
          propertyName: propertyName,
          propertyKey: propertyKey,
          className: className,
          prop: prop,
          classesWithNullableLists: classesWithNullableLists,
          allEnumNames: allEnumsNames,
          allEnumListNames: allEnumListNames,
          basicTypesMap: basicTypesMap,
          requiredProperties: requiredProperties,
          allClasses: allClasses,
          isDeprecated: isDeprecated,
        );
      case 'enum':
        return generateEnumPropertyContent(
          key: propertyName,
          className: className,
          propertyKey: propertyKey,
          allEnumNames: allEnumsNames,
          allEnumListNames: allEnumListNames,
          prop: prop,
          requiredProperties: requiredProperties,
          isDeprecated: isDeprecated,
        );
      default:
        return generateGeneralPropertyContent(
          propertyName: propertyName,
          propertyKey: propertyKey,
          className: className,
          defaultValues: defaultValues,
          prop: prop,
          allEnumNames: allEnumsNames,
          allEnumListNames: allEnumListNames,
          requiredProperties: requiredProperties,
          isDeprecated: isDeprecated,
        );
    }
  }

  String getParameterName(String name, List<String> names) {
    if (names.contains(name)) {
      final newName = '\$$name';
      return getParameterName(newName, names);
    }

    return name;
  }

  String generatePropertiesContent(
    SwaggerRoot root,
    Map<String, SwaggerSchema> propertiesMap,
    Map<String, SwaggerSchema> schemas,
    String className,
    List<DefaultValueMap> defaultValues,
    List<String> classesWithNullableLists,
    List<String> allEnumNames,
    List<String> allEnumListNames,
    List<String> requiredProperties,
    Map<String, SwaggerSchema> allClasses,
  ) {
    if (propertiesMap.isEmpty) {
      return '';
    }

    final results = <String>[];
    final propertyNames = <String>[];

    for (var i = 0; i < propertiesMap.keys.length; i++) {
      var propertyName = propertiesMap.keys.elementAt(i);

      final prop = propertiesMap[propertyName]!;

      final propertyKey = propertyName;

      final basicTypesMap = generateBasicTypesMapFromSchemas(root);

      propertyName = getValidatedParameterName(propertyName).asParameterName();

      if (propertyName.isEmpty) {
        propertyName = '\$';
      }

      propertyName = getParameterName(propertyName, propertyNames);

      propertyNames.add(propertyName);
      if (prop.type.isNotEmpty) {
        results.add(generatePropertyContentByType(
          prop,
          propertyName,
          propertyKey,
          className,
          defaultValues,
          classesWithNullableLists,
          allEnumNames,
          allEnumListNames,
          basicTypesMap,
          requiredProperties,
          allClasses,
          prop.deprecated,
        ));
      } else if (prop.allOf.isNotEmpty) {
        results.add(
          generatePropertyContentByAllOf(
            prop: prop,
            allEnumListNames: allEnumListNames,
            className: className,
            allEnumNames: allEnumNames,
            propertyKey: propertyKey,
            propertyName: propertyName,
            basicTypesMap: basicTypesMap,
            requiredProperties: requiredProperties,
          ),
        );
      } else if (prop.hasRef) {
        results.add(generatePropertyContentByRef(
          prop,
          propertyName,
          propertyKey,
          className,
          allEnumNames,
          allEnumListNames,
          basicTypesMap,
          requiredProperties,
          allClasses,
        ));
      } else if (prop.schema != null) {
        results.add(generatePropertyContentBySchema(
          prop,
          propertyName,
          propertyKey,
          className,
          allEnumNames,
          allEnumListNames,
          basicTypesMap,
          requiredProperties,
        ));
      } else {
        results.add(generatePropertyContentByDefault(
          prop: prop,
          propertyName: propertyName,
          propertyKey: propertyKey,
          allEnumNames: allEnumNames,
          allEnumListNames: allEnumListNames,
          requiredProperties: requiredProperties,
          isDeprecated: prop.deprecated,
        ));
      }
    }

    return results.join('\n');
  }

  Map<String, String> generateBasicTypesMapFromSchemas(SwaggerRoot root) {
    final result = <String, String>{};

    final components = root.components;

    final definitions = root.definitions;

    final schemas = components?.schemas ?? {};

    final responses = components?.responses ?? {};

    final allClasses = {
      ...definitions,
      ...responses,
      ...schemas,
    };

    allClasses.forEach((key, value) {
      if (kBasicTypes.contains(value.type.toLowerCase()) && !value.isEnum) {
        result.addAll(
            {key: _mapBasicTypeToDartType(value.type, value.format, options)});
      }

      if (value.type == kArray && value.items != null) {
        final ref = value.items!.ref;

        if (result[ref.getUnformattedRef()] != null) {
          result[key] = result[ref.getUnformattedRef()]!.asList();
        } else if (ref.isNotEmpty) {
          var typeName = ref.getUnformattedRef();
          final schema = allClasses[typeName];

          if (kBasicTypes.contains(schema?.type)) {
            typeName =
                _mapBasicTypeToDartType(schema!.type, value.format, options);
          } else {
            typeName = getValidatedClassName(typeName);
          }

          result[key] = typeName.asList();
        }
      }
    });

    return result;
  }

  static String _mapBasicTypeToDartType(
      String basicType, String format, GeneratorOptions options) {
    switch (basicType.toLowerCase()) {
      case 'string':
        final scalar = options.scalars[format];
        if (scalar != null) {
          return scalar.type;
        } else if (format == 'date-time' || format == 'datetime') {
          return kDateTimeType;
        } else {
          return 'String';
        }
      case 'int':
      case 'integer':
        return 'int';
      case 'double':
      case 'number':
      case 'float':
        return 'double';
      case 'bool':
      case 'boolean':
        return 'bool';
      default:
        return '';
    }
  }

  String generateConstructorPropertiesContent({
    required String className,
    required Map<String, SwaggerSchema> entityMap,
    required List<DefaultValueMap> defaultValues,
    required List<String> requiredProperties,
    required List<String> allEnumNames,
    required List<String> allEnumListNames,
  }) {
    if (entityMap.isEmpty) {
      return '';
    }

    var results = '';
    final propertyNames = <String>[];

    entityMap.forEach((key, value) {
      var fieldName = generateFieldName(
        getParameterName(
            getValidatedParameterName(key).asParameterName(), propertyNames),
      );

      propertyNames.add(fieldName);

      final isNullableProperty = options.nullableModels.contains(className) ||
          value.shouldBeNullable ||
          !requiredProperties.contains(key);

      final isRequiredProperty =
          !value.shouldBeNullable && requiredProperties.contains(key);

      if (isRequiredProperty || !isNullableProperty) {
        results += '\t\t$kRequired this.$fieldName,\n';
      } else {
        if (!options.ignoredKeys.contains(fieldName)) {
          results += '\t\tthis.$fieldName,\n';
        }
      }
    });

    return '{\n$results\n\t}';
  }

  String generateModelClassString(
    SwaggerRoot root,
    String className,
    SwaggerSchema schema,
    Map<String, SwaggerSchema> schemas,
    List<DefaultValueMap> defaultValues,
    List<String> classesWithNullableLists,
    List<String> allEnumNames,
    List<String> allEnumListNames,
    Map<String, SwaggerSchema> allClasses,
  ) {
    final properties = getModelProperties(schema, schemas, allClasses);

    final requiredProperties = _getRequired(schema, schemas);

    final generatedConstructorProperties = generateConstructorPropertiesContent(
      className: className,
      entityMap: properties,
      defaultValues: defaultValues,
      allEnumNames: allEnumNames,
      allEnumListNames: allEnumListNames,
      requiredProperties: requiredProperties,
    );

    final generatedProperties = generatePropertiesContent(
      root,
      properties,
      schemas,
      className,
      defaultValues,
      classesWithNullableLists,
      allEnumNames,
      allEnumListNames,
      requiredProperties,
      allClasses,
    );

    final validatedClassName =
        '${getValidatedClassName(className)}${options.modelPostfix}';

    final copyWithMethod =
        generateCopyWithContent(generatedProperties, validatedClassName);

    final getHashContent = generateGetHashContent(
      generatedProperties,
      validatedClassName,
      options,
    );

    final equalsOverride = generateEqualsOverride(
      generatedProperties,
      validatedClassName,
      options,
    );

    final toStringOverride = options.overrideToString
        ? '''
@override
String toString() => jsonEncode(this);
'''
        : '';

    final hasMapping = schema.discriminator?.mapping.isNotEmpty ?? false;

    final fromJson = generatedFromJson(schema, validatedClassName);

    final toJson = generateToJson(schema, validatedClassName);

    final createToJson = generateCreateToJson(schema, validatedClassName);

    // ── oneOf-interface decorations ─────────────────────────────────────────
    // For wrappers: prepend `sealed class I<wrapperName> { ... }`, inject a
    // private `_active` field + public `active` getter inside the wrapper.
    // For subtypes: append `implements IFoo[, IBar]` to the class header and
    // emit `@override T? get foo => null;` stubs for missing common props.
    final oneOfWrapperInfo = _oneOfWrappers[validatedClassName];
    final oneOfSubtypeMemberships = _oneOfSubtypes[validatedClassName] ?? const [];

    final oneOfInterfaceBlock = oneOfWrapperInfo == null
        ? ''
        : _generateSealedInterfaceBlock(oneOfWrapperInfo);

    final oneOfWrapperExtras = oneOfWrapperInfo == null
        ? ''
        : _generateWrapperActiveMembers(oneOfWrapperInfo);

    // A subtype can appear in the same wrapper's mapping under multiple
    // discriminator values (e.g. `equal` and `not_equal` both point to the
    // same payload class). That registers the same membership twice. Dedupe
    // by interface name so we don't emit `implements IFoo, IFoo`.
    final oneOfImplementsClause = oneOfSubtypeMemberships.isEmpty
        ? ''
        : ' implements ${oneOfSubtypeMemberships.map((m) => m.interface.interfaceName).toSet().join(', ')}';

    final oneOfSubtypeStubs = oneOfSubtypeMemberships.isEmpty
        ? ''
        : _generateSubtypeMissingStubs(oneOfSubtypeMemberships);

    final generatedClass = '''
$oneOfInterfaceBlock
@JsonSerializable(explicitToJson: true $createToJson)
class $validatedClassName$oneOfImplementsClause{
\t $validatedClassName($generatedConstructorProperties);\n
\t$fromJson${hasMapping ? '' : ''}\n
\t$toJson${hasMapping ? '' : ''}\n
$generatedProperties
\tstatic const fromJsonFactory = _\$${validatedClassName}FromJson;
$oneOfWrapperExtras$oneOfSubtypeStubs
$equalsOverride

$toStringOverride

$getHashContent
}
$copyWithMethod
''';

    return generatedClass;
  }

  /// Emits the `sealed class IXxx { ... }` block that lives next to a wrapper.
  String _generateSealedInterfaceBlock(OneOfInterfaceInfo info) {
    final getters = info.commonProps
        .map((p) => '\t${p.dartType}? get ${p.camelName};')
        .join('\n');
    return '''
/// Common contract for all subtypes of [${info.wrapperName}], generated from
/// the OpenAPI `oneOf` + `discriminator` declaration. All subtypes
/// (${info.subtypeNames.join(', ')}) `implements ${info.interfaceName}`,
/// which enables exhaustive pattern matching on `${info.wrapperName}.active`.
sealed class ${info.interfaceName} {
$getters
}
''';
  }

  /// Emits the `_active` private field and public `active` getter that the
  /// wrapper class exposes. Called inside the wrapper class body.
  String _generateWrapperActiveMembers(OneOfInterfaceInfo info) {
    return '\n\t${info.interfaceName}? _active;\n'
        '\t${info.interfaceName}? get active => _active;\n';
  }

  /// Emits `@override T? get foo => null;` stubs for properties that some
  /// subtype lacks but its IXxx interface requires.
  String _generateSubtypeMissingStubs(List<OneOfSubtypeMembership> ms) {
    // A subtype may participate in multiple interfaces; de-duplicate by
    // property name so we don't emit conflicting stubs.
    final seen = <String>{};
    final lines = <String>[];
    for (final m in ms) {
      for (final p in m.missingProps) {
        if (!seen.add(p.camelName)) continue;
        lines.add('\t@override ${p.dartType}? get ${p.camelName} => null;');
      }
    }
    if (lines.isEmpty) return '';
    return '\n${lines.join('\n')}\n';
  }

  String generatedFromJson(SwaggerSchema schema, String validatedClassName) {
    final hasMapping = schema.discriminator?.mapping.isNotEmpty ?? false;
    final reporterCode = '\t\tSwaggerReporterHelper.report(\'GenerateError in $validatedClassName \${ex.toString()}\');\n';
    if (hasMapping) {
      final discriminator = schema.discriminator!;
      final propertyName = discriminator.propertyName;
      final responseVar = validatedClassName.camelCase;

      // If this wrapper produces an IXxx interface, each case must also
      // populate the wrapper's `_active` field so callers get O(1) access
      // without re-scanning the 15 nullable fields on every read.
      final hasInterface = _oneOfWrappers.containsKey(validatedClassName);

      String fieldNameFor(MapEntry<String, String> entry) =>
          entry.key == 'dynamic' ? 'dynamicField' : entry.key.camelCase;

      String caseBody(MapEntry<String, String> entry) {
        final field = fieldNameFor(entry);
        final assign =
            '$responseVar.$field = _\$${entry.value.split('/').last.pascalCase}FromJson(json);';
        final activeAssign =
            hasInterface ? ' $responseVar._active = $responseVar.$field;' : '';
        return 'case \'${entry.key}\': try { $assign$activeAssign } catch(ex) {$reporterCode} break;';
      }

      return 'static $validatedClassName _\$${validatedClassName}FromJson(Map<String, dynamic> json) { '
          '\ttry { '
          'return $validatedClassName.fromJson(json);'
          '} catch(ex) {'
          '$reporterCode'
          '\t\trethrow;'
          '}'
          '}\n\n'
          '${discriminator.mapping.entries.map((entry) => '${entry.value.getRef()}? ${fieldNameFor(entry)};').join('\n')}'
          '\n\n'
          'factory $validatedClassName.fromJson(Map<String, dynamic> json) {'
          '\t\tvar $responseVar = $validatedClassName();'
          '\t\tswitch (json[\'$propertyName\']) {'
          '\t\t\t${discriminator.mapping.entries.map(caseBody).join('\n')}'
          '\t\t}'
          '\treturn $responseVar;'
          '}';
    }
    return 'factory $validatedClassName.fromJson(Map<String, dynamic> json) { '
        '\ttry { '
        '\t\treturn _\$${validatedClassName}FromJson(json);'
        '\t} catch(ex) { '
        '$reporterCode'
        '\t\trethrow;'
        '\t} '
        '}';
  }

  String generateToJson(SwaggerSchema schema, String validatedClassName) {
    final hasMapping = schema.discriminator?.mapping.isNotEmpty ?? false;
    if (hasMapping) {
      return 'static Map<String, dynamic> _\$${validatedClassName}ToJson($validatedClassName instance) { return Map<String, dynamic>();}\n\n'
          'Map<String, dynamic> toJson() =>'
          '_\$${validatedClassName}ToJson(this)'
          '\t\t\t${schema.discriminator!.mapping.entries.map((entry) => '\n..addAll(${entry.key == 'dynamic' ? 'dynamicField' : entry.key.camelCase}?.toJson() ?? {})').join('\n')};';
    }
    return 'Map<String, dynamic> toJson() => _\$${validatedClassName}ToJson(this);';
  }

  String generateCreateToJson(SwaggerSchema schema, String validatedClassName) {
    if (options.generateToJsonFor.isEmpty ||
        options.generateToJsonFor.contains(validatedClassName)) {
      return '';
    }

    return ', createToJson: false';
  }

  List<String> _getRequired(
      SwaggerSchema schema, Map<String, SwaggerSchema> schemas,
      [int recursionCount = 5]) {
    final required = <String>{};
    if (recursionCount == 0) {
      return required.toList();
    }
    for (var interface in _getInterfaces(schema)) {
      if (interface.hasRef) {
        final parentName = interface.ref.split('/').last.pascalCase;
        final parentSchema = schemas[parentName];

        required.addAll(parentSchema != null
            ? _getRequired(parentSchema, schemas, recursionCount - 1)
            : []);
      }
      required.addAll(interface.required);
    }
    required.addAll(schema.required);
    return required.toList();
  }

  List<SwaggerSchema> _getInterfaces(SwaggerSchema schema) {
    if (schema.allOf.isNotEmpty) {
      return schema.allOf;
    } else if (schema.anyOf.isNotEmpty) {
      return schema.anyOf;
    } else if (schema.oneOf.isNotEmpty) {
      return schema.oneOf;
    }
    return [];
  }

  String generateEqualsOverride(
    String generatedProperties,
    String validatedClassName,
    GeneratorOptions options,
  ) {
    if (!options.overrideEqualsAndHashcode) {
      return '';
    }

    final splittedProperties = RegExp(
      'final .+ (.+);',
    ).allMatches(generatedProperties).map((e) => e.group(1)!);

    if (splittedProperties.isEmpty) {
      return '';
    }

    final checks = splittedProperties.map((e) => '''
(identical(other.$e, $e) ||
                const DeepCollectionEquality().equals(other.$e, $e))
    ''').join(' && ');

    return '''
@override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is $validatedClassName &&
            $checks);
  }
    ''';
  }

  String generateCopyWithContent(
      String generatedProperties, String validatedClassName) {
    final splittedCopyWithProperties = RegExp(
      'final (.+) (.+);',
    ).allMatches(generatedProperties).map((e) {
      var type = e.group(1)!;
      if (!type.endsWith('?') && type != kDynamic) {
        type += '?';
      }
      return '$type ${e.group(2)!}';
    });

    final splittedCopyWithWrappedProperties = RegExp(
      'final (.+) (.+);',
    ).allMatches(generatedProperties).map((e) {
      return 'Wrapped<${e.group(1)!}>? ${e.group(2)!}';
    });

    if (splittedCopyWithProperties.isEmpty) {
      return '';
    }

    final spittedCopyWithPropertiesJoined =
        splittedCopyWithProperties.join(', ');

    final spittedCopyWithWrappedPropertiesJoined =
        splittedCopyWithWrappedProperties.join(', ');

    final splittedCopyWithPropertiesNamesContent = splittedCopyWithProperties
        .map((e) => e.substring(e.indexOf(' ') + 1))
        .map((e) => '$e: $e ?? this.$e')
        .join(',\n');

    final splittedCopyWithWrappedPropertiesNamesContent =
        splittedCopyWithWrappedProperties
            .map((e) => e.substring(e.indexOf(' ') + 1))
            .map((e) => '$e: ($e != null ? $e.value : this.$e)')
            .join(',\n');

    final copyWith =
        '$validatedClassName copyWith({$spittedCopyWithPropertiesJoined}) { return $validatedClassName($splittedCopyWithPropertiesNamesContent); }';

    final copyWithWrapped =
        '$validatedClassName copyWithWrapped({$spittedCopyWithWrappedPropertiesJoined}) { return $validatedClassName($splittedCopyWithWrappedPropertiesNamesContent); }';

    return 'extension \$${validatedClassName}Extension on $validatedClassName { $copyWith $copyWithWrapped}';
  }

  String generateGetHashContent(
    String generatedProperties,
    String validatedClassName,
    GeneratorOptions options,
  ) {
    if (!options.overrideEqualsAndHashcode) {
      return '';
    }

    final propertiesHash = RegExp(
      'final .+ (.+);',
    )
        .allMatches(generatedProperties)
        .map((e) => e.group(1)!)
        .map((e) => 'const DeepCollectionEquality().hash($e)');

    final allHashComponents =
        [...propertiesHash, 'runtimeType.hashCode'].join(' ^\n');

    return '''
@override
int get hashCode =>
$allHashComponents;
''';
  }

  Map<String, SwaggerSchema> getModelProperties(
    SwaggerSchema schema,
    Map<String, SwaggerSchema> schemas,
    Map<String, SwaggerSchema> allClasses,
  ) {
    if (schema.allOf.isEmpty) {
      return schema.properties;
    }

    final allOf = schema.allOf;

    final newModelMap = allOf.firstWhereOrNull((m) => m.properties.isNotEmpty);

    final currentProperties =
        Map<String, SwaggerSchema>.from(schema.properties);

    currentProperties.addAll(newModelMap?.properties ?? {});

    final refs = allOf.where((element) => element.ref.isNotEmpty).toList();
    for (var allOf in refs) {
      final allOfSchema = allClasses[allOf.ref.getUnformattedRef()];

      if (allOfSchema != null) {
        final properties = Map.from(allOfSchema.properties);
        for (final allOf in allOfSchema.allOf) {
          properties.addAll(allOf.properties);
        }
      }

      currentProperties.addAll(allOfSchema?.properties ?? {});
    }

    if (currentProperties.isEmpty) {
      return {};
    }

    final allOfRef = allOf.firstWhereOrNull((m) => m.hasRef);

    if (allOfRef != null) {
      final refString = allOfRef.ref;
      final schema = schemas[refString.getUnformattedRef()];

      if (schema != null) {
        if (schema.allOf.isNotEmpty) {
          final refs =
              allOf.where((element) => element.ref.isNotEmpty).toList();

          for (var allOf in refs) {
            final allOfSchema = allClasses[allOf.ref.getUnformattedRef()];

            if (allOfSchema != null) {
              currentProperties.addAll(Map.from(allOfSchema.properties));
              for (final allOf in allOfSchema.allOf) {
                currentProperties.addAll(allOf.properties);

                if (allOf.ref.isNotEmpty) {
                  final oneMoreModel =
                      allClasses[allOf.ref.getUnformattedRef()];
                  currentProperties.addAll(oneMoreModel?.properties ?? {});
                }
              }
            }

            currentProperties.addAll(allOfSchema?.properties ?? {});
          }
        }
        final moreProperties = schema.properties;

        currentProperties.addAll(moreProperties);
      }
    }

    return currentProperties;
  }

  // ===========================================================================
  // oneOf + discriminator analysis
  //
  // Pre-pass that scans every schema with `discriminator.mapping`. For each
  // such "wrapper" we compute the intersection of properties across all
  // subtypes (strict where types agree exactly; lax for properties present in
  // ≥ 80% of subtypes; transitive when a property points to refs that are
  // themselves all subtypes of another wrapper, in which case the type is
  // that wrapper's interface).
  //
  // The results populate [_oneOfWrappers] and [_oneOfSubtypes]; the emission
  // code in [generateModelClassString] then consults these maps to:
  //   - prepend a `sealed class I<wrapperName>` ahead of each wrapper class
  //   - inject `IXxx? _active;` field + `active` getter into the wrapper
  //   - add `implements IXxx` to subtype class headers
  //   - emit `@override T? get foo => null;` stubs in subtypes lacking a
  //     property that's part of the lax intersection
  // ===========================================================================

  void _buildOneOfAnalysis(Map<String, SwaggerSchema> classes) {
    _oneOfWrappers = {};
    _oneOfSubtypes = {};

    // ---- Pass 1: collect candidate wrappers and their subtype schemas ----
    final working = <String, _OneOfWorkingState>{};

    classes.forEach((rawClassName, schema) {
      final mapping = schema.discriminator?.mapping;
      if (mapping == null || mapping.isEmpty) return;
      if (mapping.length < 2) return;

      final wrapperName = getValidatedClassName(rawClassName).pascalCase;

      final subtypes = <_OneOfSubtypeRef>[];
      for (final entry in mapping.entries) {
        final refName = entry.value.split('/').last;
        final subSchema = classes[getValidatedClassName(refName)];
        if (subSchema == null) continue;
        subtypes.add(_OneOfSubtypeRef(refName.pascalCase, subSchema));
      }
      if (subtypes.length < 2) return;

      // Gather (snake_name → list of subtype-schema pairs that declare it).
      // Skip property names listed in `options.ignoredKeys` — the generator
      // filters those from subtype field emission, so promoting them to the
      // interface would yield abstract getters with no concrete impl.
      final ignored = <String>{
        ...options.ignoredKeys,
        ...options.ignoredKeys.map((k) => _safeCamelCase(k)),
      };
      final propMap = <String, List<_OneOfPropOccurrence>>{};
      for (final st in subtypes) {
        final props = _allPropsOf(st.schema, classes);
        for (final pe in props.entries) {
          if (ignored.contains(pe.key)) continue;
          propMap
              .putIfAbsent(pe.key, () => [])
              .add(_OneOfPropOccurrence(st.name, pe.value));
        }
      }

      final total = subtypes.length;
      // threshold = ceil(0.8 * total)
      final threshold = (total * 4 + 4) ~/ 5;

      working[wrapperName] = _OneOfWorkingState(
        wrapperName: wrapperName,
        subtypes: subtypes,
        propMap: propMap,
        threshold: threshold,
      );
    });

    // Reverse map: subtype name -> wrapper that owns it (for transitive pass).
    final subtypeOwner = <String, String>{};
    for (final w in working.values) {
      for (final st in w.subtypes) {
        subtypeOwner[st.name] = w.wrapperName;
      }
    }

    // ---- Pass 2a: strict + lax intersection (signatures must agree) ----
    for (final w in working.values) {
      for (final entry in w.propMap.entries) {
        final propName = entry.key;
        final occurrences = entry.value;
        if (occurrences.length < w.threshold) continue;

        // Inline enums (e.g. `{type: string, enum: ['evm']}`) get materialized
        // by the generator as a per-class enum (`EvmVaultTypeGenerated`) that
        // diverges across subtypes even when the raw schema's type/format
        // matches. Reject any prop where *any* occurrence carries an inline
        // enum so we don't promise `String?` to consumers and then get
        // `enums.XxxTypeGenerated` from the subtype's actual field.
        if (occurrences.any((o) => _hasInlineEnum(o.schema))) continue;

        final firstSig = _schemaSignature(occurrences.first.schema);
        final allAgree =
            occurrences.every((o) => _schemaSignature(o.schema) == firstSig);
        if (!allAgree) continue;

        final dartType = _schemaToDartType(occurrences.first.schema, classes);
        if (dartType == kDynamic) continue;

        w.commonProps.add(OneOfCommonProp(
          snakeName: propName,
          camelName: _safeCamelCase(propName),
          dartType: dartType,
        ));
        w.acceptedPropNames.add(propName);
      }
    }

    // ---- Pass 2b: transitive — a prop where all occurrences are refs to
    // ---- subtypes of THE SAME other wrapper W can be exposed as IW? ----
    for (final w in working.values) {
      for (final entry in w.propMap.entries) {
        final propName = entry.key;
        if (w.acceptedPropNames.contains(propName)) continue;

        final occurrences = entry.value;
        if (occurrences.length < w.threshold) continue;
        if (!occurrences.every((o) => o.schema.hasRef)) continue;

        final ownerSet = <String>{};
        for (final o in occurrences) {
          final refName = o.schema.ref.split('/').last.pascalCase;
          final owner = subtypeOwner[refName];
          if (owner == null) {
            ownerSet.clear();
            break;
          }
          ownerSet.add(owner);
        }
        if (ownerSet.length != 1) continue;
        final commonOwner = ownerSet.first;
        // The owner wrapper must itself end up with a non-empty interface,
        // otherwise IW won't be emitted. We can't fully verify that yet,
        // but require commonProps > 0 at this point as a proxy.
        final ownerState = working[commonOwner];
        if (ownerState == null || ownerState.commonProps.isEmpty) continue;

        w.commonProps.add(OneOfCommonProp(
          snakeName: propName,
          camelName: _safeCamelCase(propName),
          dartType: 'I$commonOwner',
        ));
        w.acceptedPropNames.add(propName);
      }
    }

    // ---- Pass 3: finalize. Skip wrappers with no common props. ----
    for (final w in working.values) {
      if (w.commonProps.isEmpty) continue;

      final info = OneOfInterfaceInfo(
        wrapperName: w.wrapperName,
        interfaceName: 'I${w.wrapperName}',
        commonProps: List.unmodifiable(w.commonProps),
        subtypeNames: w.subtypes.map((s) => s.name).toList(growable: false),
      );
      _oneOfWrappers[w.wrapperName] = info;

      for (final st in w.subtypes) {
        final declared = _allPropsOf(st.schema, classes);
        final missing = info.commonProps
            .where((p) => !declared.containsKey(p.snakeName))
            .toList(growable: false);
        _oneOfSubtypes
            .putIfAbsent(st.name, () => [])
            .add(OneOfSubtypeMembership(
              interface: info,
              missingProps: missing,
            ));
      }
    }
  }

  /// Collects all schema properties of [schema], merging properties from any
  /// `allOf` references (resolved via [schemas]). Recursion is bounded.
  Map<String, SwaggerSchema> _allPropsOf(
    SwaggerSchema schema,
    Map<String, SwaggerSchema> schemas, [
    int depth = 5,
  ]) {
    if (depth == 0) return {};
    final result = <String, SwaggerSchema>{};
    for (final part in schema.allOf) {
      if (part.hasRef) {
        final refName = part.ref.split('/').last;
        final refSchema = schemas[getValidatedClassName(refName)];
        if (refSchema != null) {
          result.addAll(_allPropsOf(refSchema, schemas, depth - 1));
        }
      } else {
        result.addAll(part.properties);
      }
    }
    result.addAll(schema.properties);
    return result;
  }

  /// A normalized signature string used to decide whether two property
  /// schemas are "the same type" across subtypes. Equal signatures imply the
  /// generator will emit the same Dart type for them.
  String _schemaSignature(SwaggerSchema s) {
    if (s.hasRef) return 'ref:${s.ref.split('/').last}';
    if (s.type == 'array') {
      final items = s.items;
      return 'array<${items == null ? '' : _schemaSignature(items)}>';
    }
    final type = s.type;
    if (type.isEmpty) return 'unknown';
    return '$type:${s.format}';
  }

  /// Maps a property's schema to the Dart type string used in the generated
  /// interface getter. Always returned WITHOUT a trailing `?`; the caller
  /// appends `?` when emitting the getter.
  String _schemaToDartType(
      SwaggerSchema s, Map<String, SwaggerSchema> schemas) {
    if (s.hasRef) {
      final refName = s.ref.split('/').last;
      final pascal = refName.pascalCase;
      final refSchema = schemas[getValidatedClassName(refName)];
      if (refSchema?.isEnum == true) return 'enums.$pascal';
      return pascal;
    }
    if (s.type == 'array') {
      final items = s.items;
      final inner =
          items != null ? _schemaToDartType(items, schemas) : 'Object';
      return 'List<$inner>';
    }
    switch (s.type) {
      case 'string':
        if (s.format == 'date-time') return 'DateTime';
        return 'String';
      case 'integer':
        return 'int';
      case 'number':
        return 'double';
      case 'boolean':
        return 'bool';
      case 'object':
        return 'Map<String, dynamic>';
      default:
        return kDynamic;
    }
  }

  /// camelCase that survives identifiers starting with an underscore or
  /// reserved words. Falls back to the raw name if camelCase would empty it.
  String _safeCamelCase(String name) {
    final camel = name.camelCase;
    return camel.isEmpty ? name : camel;
  }

  /// True when [s] declares an inline enum (i.e. has explicit `enum` values
  /// but no `$ref` to a shared enum schema). Such props get materialized as
  /// a per-class generated enum (e.g. `EvmVaultTypeGenerated`), so two
  /// subtypes that look schema-identical still diverge in Dart and must be
  /// excluded from the shared interface.
  bool _hasInlineEnum(SwaggerSchema s) =>
      !s.hasRef && s.enumValuesObj.isNotEmpty;

  Map<String, SwaggerSchema> getRequestBodiesFromRequests(SwaggerRoot root) {
    final paths = root.paths;
    if (paths.isEmpty) {
      return {};
    }

    final result = <String, SwaggerSchema>{};

    paths.forEach((pathKey, path) {
      path.requests.forEach((requestKey, request) {
        if (!supportedRequestTypes.contains(requestKey)) {
          return;
        }

        final content = request.requestBody?.content;
        if (content != null) {
          final schema = content.schema;
          if (schema != null) {
            if (schema.type == kObject && schema.properties.isNotEmpty) {
              final className = '${pathKey.pascalCase}${requestKey.pascalCase}';

              result[getValidatedClassName(className)] = schema;
            }
          }
        }
      });
    });

    return result;
  }
}

class JsonEnumValue {
  JsonEnumValue({
    required this.jsonKey,
    required this.fromJson,
  });

  final String jsonKey;
  final String fromJson;
}

/// A property in the common interface for an `oneOf` + `discriminator` wrapper.
/// Emitted as a nullable getter on the generated abstract interface.
class OneOfCommonProp {
  OneOfCommonProp({
    required this.snakeName,
    required this.camelName,
    required this.dartType,
  });

  /// Original schema property name (e.g. "derivation_path").
  final String snakeName;

  /// Camel-cased property name used in Dart (e.g. "derivationPath").
  final String camelName;

  /// Dart type of the getter, WITHOUT trailing `?`. The interface always
  /// declares getters as nullable, so callers see `T?`.
  /// E.g. "String", "DateTime", "List<OwnedAsset>", "enums.MpcVaultState",
  /// "IEnrichedChain" (transitive case).
  final String dartType;
}

/// Describes one wrapper class with `oneOf` + `discriminator` and the
/// `sealed class I<wrapperName>` interface to emit alongside it.
class OneOfInterfaceInfo {
  OneOfInterfaceInfo({
    required this.wrapperName,
    required this.interfaceName,
    required this.commonProps,
    required this.subtypeNames,
  });

  /// PascalCase name of the wrapper class (e.g. "Vault").
  final String wrapperName;

  /// Name of the generated interface class (e.g. "IVault").
  final String interfaceName;

  /// Common properties intersected across all subtypes of the discriminator.
  final List<OneOfCommonProp> commonProps;

  /// PascalCase names of all subtypes participating in the discriminator
  /// mapping (e.g. ["EvmVault", "SolanaVault", ...]).
  final List<String> subtypeNames;
}

/// Marks a subtype class that participates in a `oneOf` + `discriminator`
/// wrapper. It must `implements <interface.interfaceName>` and provide
/// `@override T? get name => null;` stubs for any common property it lacks.
class OneOfSubtypeMembership {
  OneOfSubtypeMembership({
    required this.interface,
    required this.missingProps,
  });

  final OneOfInterfaceInfo interface;

  /// Properties present in `interface.commonProps` that this subtype's
  /// schema does NOT declare. Each needs an explicit null-returning getter
  /// override to satisfy the interface contract.
  final List<OneOfCommonProp> missingProps;
}

/// Internal scratch state for [SwaggerModelsGenerator._buildOneOfAnalysis].
/// Holds per-wrapper working sets while the multi-pass intersection runs.
class _OneOfWorkingState {
  _OneOfWorkingState({
    required this.wrapperName,
    required this.subtypes,
    required this.propMap,
    required this.threshold,
  });

  final String wrapperName;
  final List<_OneOfSubtypeRef> subtypes;
  final Map<String, List<_OneOfPropOccurrence>> propMap;
  final int threshold;

  final List<OneOfCommonProp> commonProps = [];
  final Set<String> acceptedPropNames = {};
}

class _OneOfSubtypeRef {
  _OneOfSubtypeRef(this.name, this.schema);
  final String name;
  final SwaggerSchema schema;
}

class _OneOfPropOccurrence {
  _OneOfPropOccurrence(this.subtypeName, this.schema);
  final String subtypeName;
  final SwaggerSchema schema;
}
