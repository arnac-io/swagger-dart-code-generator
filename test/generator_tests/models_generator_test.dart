import 'dart:io';

import 'package:swagger_dart_code_generator/src/code_generators/swagger_models_generator.dart';
import 'package:swagger_dart_code_generator/src/code_generators/v2/swagger_models_generator_v2.dart';
import 'package:swagger_dart_code_generator/src/code_generators/v3/swagger_models_generator_v3.dart';
import 'package:swagger_dart_code_generator/src/models/generator_options.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/responses/swagger_schema.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/swagger_root.dart';
import 'package:test/test.dart';

import '../code_examples.dart';

void main() {
  final generator = SwaggerModelsGeneratorV3(
    GeneratorOptions(
      inputFolder: '',
      outputFolder: '',
    ),
  );
  final generator2 = SwaggerModelsGeneratorV2(
    GeneratorOptions(
      inputFolder: '',
      outputFolder: '',
    ),
  );

  final generator3 = SwaggerModelsGeneratorV2(
    GeneratorOptions(
      inputFolder: '',
      outputFolder: '',
      overrideEqualsAndHashcode: false,
    ),
  );

  group('generateDefaultValueFromMap', () {
    test('Should return default value', () {
      const defaultValue = 'true';
      const typeName = 'bool';
      const expectedResult = 'true';
      final result = generator.generateDefaultValueFromMap(
          DefaultValueMap(defaultValue: defaultValue, typeName: typeName));

      expect(result, contains(expectedResult));
    });

    test('Should return default from switch', () {
      const defaultValue = 'Animal';
      const typeName = 'Object';
      const expectedResult = 'Animal';
      final result = generator.generateDefaultValueFromMap(
          DefaultValueMap(defaultValue: defaultValue, typeName: typeName));

      expect(result, contains(expectedResult));
    });
  });

  group('getParameterTypeName', () {
    test('Should return validate parameter type name', () {
      const className = 'Animal';
      const parameterName = 'orderId';
      final parameter = SwaggerSchema(type: 'object');
      const expectedResult = 'Object';
      final result = generator.getParameterTypeName(
          className, parameterName, parameter, '', null);

      expect(result, contains(expectedResult));
    });

    test('Should return Object, because we dont jave map[items]', () {
      const className = 'Animal';
      const parameterName = 'orderId';
      final parameter = SwaggerSchema(type: 'array');
      const expectedResult = 'Object';
      final result = generator.getParameterTypeName(
          className, parameterName, parameter, '', null);

      expect(result, contains(expectedResult));
    });

    test('Should return Object, because we have map[oneOf]', () {
      const className = 'Animal';
      const parameterName = 'orderId';
      final parameter = SwaggerSchema(oneOf: [SwaggerSchema(type: 'animals')]);
      const expectedResult = 'Object';
      final result = generator.getParameterTypeName(
          className, parameterName, parameter, '', null);

      expect(result, contains(expectedResult));
    });

    test('Should return Object', () {
      const className = 'Animal';
      const parameterName = 'orderId';
      const expectedResult = 'Object';
      final result = generator.getParameterTypeName(
          className, parameterName, null, '', null);

      expect(result, contains(expectedResult));
    });

    test('Should return validate parameter type name', () {
      const className = 'Animal';
      const parameterName = 'orderId';
      final parameter = SwaggerSchema(ref: '#/definitions/Pet');
      const expectedResult = 'Pet';
      final result = generator.getParameterTypeName(
          className, parameterName, parameter, '', null);

      expect(result, contains(expectedResult));
    });

    test('Should return optional name parameter', () {
      const className = 'Animal';
      const parameterName = 'orderId';
      const refNameParameter = 'animals_Object';
      const expectedResult = 'AnimalsObject';
      final result = generator.getParameterTypeName(
          className, parameterName, null, '', refNameParameter);

      expect(result, contains(expectedResult));
    });

    test('Should return DateTime', () {
      const className = 'Animal';
      const parameterName = 'orderId';
      final parameter = SwaggerSchema(type: 'string', format: 'date-time');
      const expectedResult = 'DateTime';
      final result = generator.getParameterTypeName(
          className, parameterName, parameter, '', null);

      expect(result, contains(expectedResult));
    });

    test('Should return Uuid', () {
      final generator = SwaggerModelsGeneratorV2(
        GeneratorOptions(
          inputFolder: '',
          outputFolder: '',
          importPaths: [
            'package:uuid/uuid.dart',
          ],
          scalars: {
            'uuid': CustomScalar(type: 'Uuid', deserialize: 'parse')
          }
        ),
      );
      const className = 'Person';
      const parameterName = 'id';
      final parameter = SwaggerSchema(type: 'string', format: 'uuid');
      const expectedResult = 'Uuid';
      final result = generator.getParameterTypeName(
          className, parameterName, parameter, '', null);

      expect(result, contains(expectedResult));
    });
  });

  group('generateFieldName', () {
    test('Should return validate field name', () {
      const name = 'Cat_Dog-Animals';
      const expectedResult = 'catDogAnimals';
      final result = generator.generateFieldName(name);

      expect(result, contains(expectedResult));
    });

    test('Should return \$forbiddenFieldName', () {
      const name = '#';
      const expectedResult = '\$forbiddenFieldName';
      final result = generator.generateFieldName(name);

      expect(result, contains(expectedResult));
    });

    test('Should return \$null', () {
      const name = 'null';
      const expectedResult = '\$null';
      final result = generator.generateFieldName(name);

      expect(result, contains(expectedResult));
    });

    test('Should return \$number', () {
      const name = '5element';
      const expectedResult = '\$5element';
      final result = generator.generateFieldName(name);

      expect(result, contains(expectedResult));
    });
  });

  group('generatePropertyContentByDefault', () {
    test('Should return property with JsonKey', () {
      final propertyEntryMap = SwaggerSchema(originalRef: 'Pet');
      const propertyName = 'shipDate';
      const jsonKeyExpendedResult = "@JsonKey(name: '$propertyName'";
      final result = generator.generatePropertyContentByDefault(
        prop: propertyEntryMap,
        propertyName: propertyName,
        propertyKey: propertyName,
        allEnumNames: [],
        allEnumListNames: [],
        requiredProperties: [],
        isDeprecated: false,
      );

      expect(result, contains(jsonKeyExpendedResult));
    });

    test('Should generate includeIfNull if option is true', () {
      final propertyEntryMap = SwaggerSchema(originalRef: 'Pet');
      const propertyName = 'shipDate';
      final result = SwaggerModelsGeneratorV3(GeneratorOptions(
        inputFolder: '',
        outputFolder: '',
        includeIfNull: false,
      )).generatePropertyContentByDefault(
        prop: propertyEntryMap,
        propertyName: propertyName,
        propertyKey: propertyName,
        allEnumNames: [],
        allEnumListNames: [],
        requiredProperties: [],
        isDeprecated: false,
      );

      expect(result, contains(', includeIfNull: false'));
    });

    test('Should NOT generate includeIfNull if option is false', () {
      final propertyEntryMap = SwaggerSchema(originalRef: 'Pet');
      const propertyName = 'shipDate';
      final result = generator.generatePropertyContentByDefault(
        prop: propertyEntryMap,
        propertyName: propertyName,
        propertyKey: propertyName,
        allEnumNames: [],
        allEnumListNames: [],
        requiredProperties: [],
        isDeprecated: false,
      );

      expect(result.contains(', includeIfNull: false'), equals(false));
    });
  });

  group('generateModelClassContent', () {
    test('Should return model class content', () {
      final map = SwaggerSchema.fromJson({});
      const className = 'Animals';
      const classExpectedResult = 'class Animals{';
      const factoryConstructorExpectedResult =
          '\tfactory Animals.fromJson(Map<String, dynamic> json) => _\$AnimalsFromJson(json);\n';
      final result = generator.generateModelClassContent(
        SwaggerRoot.empty,
        className,
        map,
        {},
        <DefaultValueMap>[],
        [],
        [],
        [],
        {},
        'fle_name',
      );

      expect(result, contains(classExpectedResult));
      expect(result, contains(factoryConstructorExpectedResult));
    });

    test('Should return model class content', () {
      final map = SwaggerSchema.fromJson({});
      const className = 'Animals';
      const classExpectedResult = 'class Animals{';
      const factoryConstructorExpectedResult =
          '\tfactory Animals.fromJson(Map<String, dynamic> json) => _\$AnimalsFromJson(json);\n';
      final result = generator2.generateModelClassContent(
        SwaggerRoot.empty,
        className,
        map,
        {},
        <DefaultValueMap>[],
        [],
        [],
        [],
        {},
        'fle_name',
      );

      expect(result, contains(classExpectedResult));
      expect(result, contains(factoryConstructorExpectedResult));
    });
  });

  group('generateConstructorPropertiesContent', () {
    test('Should return empty', () {
      const expectedResult = '';
      final result = generator.generateConstructorPropertiesContent(
        className: '',
        entityMap: {},
        defaultValues: [],
        requiredProperties: [],
        allEnumNames: [],
        allEnumListNames: [],
      );

      expect(result, contains(expectedResult));
    });

    test('Should return validate constructor property', () {
      final map = <String, SwaggerSchema>{'Animal': SwaggerSchema()};
      const expectedResult = 'this.animal';
      final result = generator.generateConstructorPropertiesContent(
        className: '',
        entityMap: map,
        defaultValues: [],
        requiredProperties: [],
        allEnumNames: [],
        allEnumListNames: [],
      );

      expect(result, contains(expectedResult));
    });
  });

  group('generatePropertyContentBySchema', () {
    test('Should return property content by schema', () {
      final map = SwaggerSchema(schema: SwaggerSchema(ref: 'Pet'));
      const propertyName = 'dog';
      const className = 'Animals';
      const propertyKey = 'Dog';
      const jsonKeyExpectedResult = "\t@JsonKey(name: 'Dog')\n";
      const fieldExpectedResult = '\tfinal Pet dog';
      final result = generator.generatePropertyContentBySchema(
        map,
        propertyName,
        propertyKey,
        className,
        [],
        [],
        {},
        [],
      );

      expect(result, contains(jsonKeyExpectedResult));
      expect(result, contains(fieldExpectedResult));
    });
  });

  group('generatePropertyContents', () {
    test('Should return properties from ref', () {
      final map = {
        'Animals': SwaggerSchema(ref: '#/definitions/Pet'),
      };

      const className = 'Animals';
      const jsonKeyExpectedResult = "\t@JsonKey(name: 'Animals')\n";
      const fieldExpectedResult = 'final Pet? animals';
      final result = generator.generatePropertyContents(
        SwaggerRoot.empty,
        map,
        {},
        className,
        <DefaultValueMap>[],
        [],
        [],
        [],
        [],
        {},
      ).join('\n');

      expect(result, contains(jsonKeyExpectedResult));
      expect(result, contains(fieldExpectedResult));
    });

    test('Should return properties from schema', () {
      final map = {
        'Animals': SwaggerSchema(
          schema: SwaggerSchema(ref: '#/definitions/Pet'),
        )
      };

      const className = 'Animals';
      const jsonKeyExpectedResult = "\t@JsonKey(name: 'Animals')\n";
      const fieldExpectedResult = 'final Pet animals';
      final result = generator.generatePropertyContents(
        SwaggerRoot.empty,
        map,
        {},
        className,
        <DefaultValueMap>[],
        [],
        [],
        [],
        [],
        {},
      ).join('\n');

      expect(result, contains(jsonKeyExpectedResult));
      expect(result, contains(fieldExpectedResult));
    });

    test('Should return properties from default originalRef', () {
      final map = {
        'Animals': SwaggerSchema(originalRef: 'Pet'),
      };

      const className = 'Animals';
      const jsonKeyExpectedResult = "\t@JsonKey(name: 'Animals')\n";
      const fieldExpectedResult = 'final Pet animals';
      final result = generator.generatePropertyContents(
        SwaggerRoot.empty,
        map,
        {},
        className,
        <DefaultValueMap>[],
        [],
        [],
        [],
        [],
        {},
      ).join('\n');

      expect(result, contains(jsonKeyExpectedResult));
      expect(result, contains(fieldExpectedResult));
    });

    test('Should return property \$with', () {
      final map = {
        'with': SwaggerSchema(originalRef: 'Pet'),
      };

      const className = 'Animals';
      const jsonKeyExpectedResult = "\t@JsonKey(name: 'with')\n";
      const fieldExpectedResult = 'final Pet \$with';
      final result = generator.generatePropertyContents(
        SwaggerRoot.empty,
        map,
        {},
        className,
        <DefaultValueMap>[],
        [],
        [],
        [],
        [],
        {},
      ).join('\n');

      expect(result, contains(jsonKeyExpectedResult));
      expect(result, contains(fieldExpectedResult));
    });
  });

  group('generateListPropertyContent', () {
    test('Should return List<Object>', () {
      final map = SwaggerSchema(items: null);
      const propertyName = 'dog';
      const className = 'Animals';
      const propertyKey = 'Dog';
      const jsonKeyExpectedResult =
          "@JsonKey(name: 'Dog', defaultValue: <Object>[])";

      const propertyExpectedResult = 'final List<Object>? dog';
      final result = generator.generateListPropertyContent(
        propertyName: propertyName,
        propertyKey: propertyKey,
        className: className,
        prop: map,
        classesWithNullableLists: [],
        allEnumNames: [],
        allEnumListNames: [],
        basicTypesMap: {},
        requiredProperties: [],
        allClasses: {},
        isDeprecated: false,
      );

      expect(result, contains(jsonKeyExpectedResult));
      expect(result, contains(propertyExpectedResult));
    });

    test('Should add fromJson and toJson', () {
      final map = SwaggerSchema(items: SwaggerSchema(originalRef: 'Dog'));
      const propertyName = 'dog';
      const className = 'Animals';
      const propertyKey = 'Dog';
      final result = generator.generateListPropertyContent(
        propertyName: propertyName,
        propertyKey: propertyKey,
        className: className,
        prop: map,
        classesWithNullableLists: [],
        allEnumNames: ['Dog'],
        allEnumListNames: [],
        basicTypesMap: {},
        requiredProperties: [],
        allClasses: {},
        isDeprecated: false,
      );

      expect(
          result, contains('toJson: dogListToJson, fromJson: dogListFromJson'));
    });

    test('Should return List<Object>', () {
      final map =
          SwaggerSchema(items: SwaggerSchema(originalRef: 'TestOriginalRef'));
      const propertyName = 'dog';
      const className = 'Animals';
      const propertyKey = 'Dog';

      final result = generator.generateListPropertyContent(
        propertyName: propertyName,
        propertyKey: propertyKey,
        className: className,
        prop: map,
        classesWithNullableLists: [],
        allEnumNames: [],
        allEnumListNames: [],
        basicTypesMap: {},
        requiredProperties: [],
        allClasses: {},
        isDeprecated: false,
      );

      expect(result, contains('final List<TestOriginalRef>? dog;'));
    });

    test('Should return List<Object> by ref', () {
      final map =
          SwaggerSchema(items: SwaggerSchema(ref: '#/definitions/TestObject'));
      const propertyName = 'dog';
      const className = 'Animals';
      const propertyKey = 'Dog';

      final result = generator.generateListPropertyContent(
        propertyName: propertyName,
        propertyKey: propertyKey,
        className: className,
        prop: map,
        classesWithNullableLists: [],
        allEnumNames: [],
        allEnumListNames: [],
        basicTypesMap: {},
        requiredProperties: [],
        allClasses: {},
        isDeprecated: false,
      );

      expect(result, contains('final List<TestObject>? dog;'));
    });
  });

  group('generateEqualsOverride', () {
    const fields = [(type: 'String', name: 'foo')];

    test('is empty when overrideEqualsAndHashcode is false', () {
      final result = generator3.generateEqualsOverride(
        fields,
        'Animals',
        generator3.options,
      );

      expect(result, isEmpty);
    });

    test('is empty for a class without fields', () {
      final result = generator.generateEqualsOverride(
        [],
        'Animals',
        generator.options,
      );

      expect(result, isEmpty);
    });

    test('compares collections deeply and other fields with ==', () {
      final expected = '''
@override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Animals &&
            other.runtimeType == runtimeType &&
            other.foo == this.foo &&
            const DeepCollectionEquality().equals(other.tags, this.tags));
  }
    ''';
      final result = generator.generateEqualsOverride(
        [...fields, (type: 'List<String>?', name: 'tags')],
        'Animals',
        generator.options,
      );

      expect(result, expected);
    });

    test('skips the identity shortcut when a field is named identical', () {
      final expected = '''
@override
  bool operator ==(Object other) {
    return (other is Animals &&
            other.runtimeType == runtimeType &&
            other.identical == this.identical);
  }
    ''';
      final result = generator.generateEqualsOverride(
        [(type: 'bool?', name: 'identical')],
        'Animals',
        generator.options,
      );

      expect(result, expected);
    });
  });

  group('generateGetHashContent', () {
    test('is empty for a class without fields', () {
      expect(generator.generateGetHashContent([], 'Animals', generator.options),
          isEmpty);
    });

    test('hashes the same fields == compares', () {
      final result = generator.generateGetHashContent(
        [(type: 'String', name: 'foo'), (type: 'List<String>?', name: 'tags')],
        'Animals',
        generator.options,
      );

      expect(
          result,
          contains('Object.hash(runtimeType,\nthis.foo,\n'
              'const DeepCollectionEquality().hash(this.tags))'));
    });

    test('hashes a list once there are more values than Object.hash takes', () {
      final result = generator.generateGetHashContent(
        [for (var i = 0; i < 20; i++) (type: 'int', name: 'f$i')],
        'Animals',
        generator.options,
      );

      expect(result, contains('Object.hashAll([runtimeType,'));
    });
  });

  group('parseFieldDeclaration', () {
    final cases = <(String, String, ModelField?)>[
      ('plain', "\t@JsonKey(name: 'id')\n\t String id;", (type: 'String', name: 'id')),
      (
        'generic type with a space',
        "@JsonKey(name: 'meta', includeIfNull: false)\n\tMap<String, Object>? meta;",
        (type: 'Map<String, Object>?', name: 'meta'),
      ),
      (
        'deprecated, default list value',
        "\t@JsonKey(name: 'ids', defaultValue: <Ref>[])\n@deprecated\tList<Ref> ids;",
        (type: 'List<Ref>', name: 'ids'),
      ),
      (
        'converter and parens inside a quoted key',
        "\t@_\$UuidJsonConverter()@JsonKey(name: 'a(b);') Uuid? id;",
        (type: 'Uuid?', name: 'id'),
      ),
      (
        'enum with a trailing default-value helper',
        "@JsonKey(name: 'kind', fromJson: kindFromJson)\n enums.Kind kind;\n\nstatic enums.Kind kindFromJson(Object? value) => x(value);",
        (type: 'enums.Kind', name: 'kind'),
      ),
      (
        'final and late modifiers',
        "@JsonKey(name: 'id')\n late final String id;",
        (type: 'String', name: 'id'),
      ),
      ('ignored key', '', null),
      ('no declaration', "@JsonKey(name: 'id'", null),
    ];

    for (final (name, content, expected) in cases) {
      test(name, () {
        expect(generator.parseFieldDeclaration(content), expected);
      });
    }
  });

  group('Tests for getValidatedClassName', () {
    test('Should', () {
      final result = generator.getValidatedClassName('Request');

      expect(result, equals('Request\$'));
    });
  });

  group('Tests for generateResponses', () {
    test('Should generate empty string for V2', () {
      final map = SwaggerRoot.parse(schemasResponsesWithResponse);
      final result = generator2.generate(
        root: map,
        fileName: 'fileName',
        allEnums: [],
      );

      expect(result, equals(''));
    });
  });

  group('Tests for models from responses', () {
    test('Should generate correct model from response', () {
      final map = SwaggerRoot.parse(requestWithReturnTypeInjected);
      final result = generator.generate(
        root: map,
        fileName: 'fileName',
        allEnums: [],
      );

      expect(result, contains('class ModelItemsGet\$Response'));
    });
  });

  group('Tests for additionalProperties', () {
    test('Should generate dynamic map type', () {
      final map = SwaggerRoot.parse(objectWithadditionalProperties);

      final result = generator.generate(
        root: map,
        fileName: 'fileName',
        allEnums: [],
      );

      expect(result, contains('final Map<String,dynamic>? metadata'));
    });

    test('keeps null values of an anyOf value schema', () {
      final map = SwaggerRoot.parse(objectWithAnyOfAdditionalProperties);

      final result = generator.generate(
        root: map,
        fileName: 'fileName',
        allEnums: [],
      );

      expect(result, contains('Map<String, Object?>? metadata'));
      expect(result, isNot(contains('Map<String, Object>? metadata')));
    });
  });

  group('Tests for overridden format types', () {
    test('Should include deserialize function in JsonKey annotation', () {
      final map = SwaggerRoot.parse(schemasWithUuidsInProperties);
      final generator = SwaggerModelsGeneratorV3(
        GeneratorOptions(
          inputFolder: '',
          outputFolder: '',
          scalars: {
            'uuid': CustomScalar(
              type: 'Uuid',
              deserialize: 'Uuid.parse',
            ),
          },
        ),
      );

      final result = generator.generate(
        root: map,
        fileName: 'fileName',
        allEnums: [],
      );

      expect(result, contains(RegExp(r'''@_\$UuidJsonConverter\(\)\s*@JsonKey\(name: 'id'\)\s*final Uuid\? id;''')));
      expect(result, contains(RegExp(r'''@_\$UuidJsonConverter\(\)\s*@JsonKey\(name: 'list', defaultValue: <Uuid>\[\]\)\s*final List<Uuid>\? list;''')));
      expect(result, contains('class _\$UuidJsonConverter implements json.JsonConverter<Uuid, String>'));
      expect(result, contains('fromJson(json) => Uuid.parse(json);'));
      expect(result, contains('toJson(json) => json.toString();'));
    });

    test('Should include serialize/deserialize functions in JsonKey annotation', () {
      final map = SwaggerRoot.parse(schemasWithUuidsInProperties);
      final generator = SwaggerModelsGeneratorV3(
        GeneratorOptions(
          inputFolder: '',
          outputFolder: '',
          scalars: {
            'uuid': CustomScalar(
              type: 'Uuid',
              deserialize: 'customUuidParse',
              serialize: 'customUuidToString',
            ),
          },
        ),
      );

      final result = generator.generate(
        root: map,
        fileName: 'fileName',
        allEnums: [],
      );

      expect(result, contains(RegExp(r'''@_\$UuidJsonConverter\(\)\s*@JsonKey\(name: 'id'\)\s*final Uuid\? id;''')));
      expect(result, contains('class _\$UuidJsonConverter implements json.JsonConverter<Uuid, String>'));
      expect(result, contains('fromJson(json) => customUuidParse(json);'));
      expect(result, contains('toJson(json) => customUuidToString(json);'));
    });
  });

  group('toString summary', () {
    const spec = '''
{
  "openapi": "3.0.1",
  "info": {"title": "t", "version": "1"},
  "paths": {},
  "components": {
    "schemas": {
      "Child": {
        "type": "object",
        "properties": {"id": {"type": "string"}, "seed": {"type": "string"}}
      },
      "Share": {
        "type": "object",
        "properties": {
          "id": {"type": "string"},
          "state": {"type": "string", "enum": ["active", "revoked"]},
          "status": {"type": "integer"},
          "type": {"\$ref": "#/components/schemas/Child"},
          "tags": {"type": "array", "items": {"type": "string"}},
          "encrypted_share": {"type": "string"}
        }
      },
      "Item": {
        "oneOf": [
          {"\$ref": "#/components/schemas/Share"},
          {"\$ref": "#/components/schemas/Child"}
        ],
        "discriminator": {
          "propertyName": "kind",
          "mapping": {
            "share": "#/components/schemas/Share",
            "child": "#/components/schemas/Child"
          }
        }
      }
    }
  }
}
''';

    SwaggerModelsGeneratorV3 generatorWith(List<String> fields,
            {bool overrideToString = true}) =>
        SwaggerModelsGeneratorV3(GeneratorOptions(
          inputFolder: '',
          outputFolder: '',
          toStringFields: fields,
          overrideToString: overrideToString,
        ));

    String generateWith(List<String> fields, {bool overrideToString = true}) =>
        generatorWith(fields, overrideToString: overrideToString).generate(
          root: SwaggerRoot.parse(spec),
          fileName: 'fileName',
          allEnums: [],
        );

    test('never serializes a model in toString, whatever the options', () {
      for (final fields in [<String>[], ['id', 'encrypted_share']]) {
        for (final overrideToString in [true, false]) {
          final result =
              generateWith(fields, overrideToString: overrideToString);

          expect(result, isNot(contains('jsonEncode(this)')));
        }
      }
    });

    test('prints only allow-listed top-level scalar fields', () {
      final result = generateWith(['id', 'state', 'status', 'type', 'tags']);

      expect(
          result,
          contains("String toString() => "
              "'Share(id: \${id}, state: \${state?.name}, status: \${status})';"));
      expect(result,
          contains("String toString() => 'Child(id: \${id})';"));
    });

    test('prints the bare class name when no fields are allow-listed', () {
      final result = generateWith([]);

      expect(result, contains("String toString() => 'Share()';"));
    });

    test('delegates a wrapper to its decoded variant', () {
      final result = generateWith(['id']);

      expect(
          result,
          contains('if (share != null) return share.toString();\n'
              '\t\tif (child != null) return child.toString();\n'
              "\t\treturn 'Item(variant: \${undecodedJson == null ? 'none' : 'unknown'})';"));
    });

    test('escapes a dollar sign in the class name', () {
      final override = generatorWith(['id']).generateToStringOverride(
          r'Type$', [(key: 'id', field: (type: 'String?', name: 'id'))], [], []);

      expect(override, contains(r"""String toString() => 'Type\$(id: ${id})';"""));
    });

    test('skips an allow-listed key that ignored_keys dropped', () {
      final result = SwaggerModelsGeneratorV3(GeneratorOptions(
        inputFolder: '',
        outputFolder: '',
        toStringFields: ['id', 'encrypted_share'],
        ignoredKeys: ['encrypted_share'],
      )).generate(
        root: SwaggerRoot.parse(spec),
        fileName: 'fileName',
        allEnums: [],
      );

      expect(result, contains("String toString() => 'Share(id: \${id})';"));
    });

    test('emits no toString when override_to_string is off', () {
      final result = generateWith(['id'], overrideToString: false);

      expect(result, isNot(contains('String toString()')));
    });

    test('rejects an allow-list entry that is not a plain JSON key', () {
      expect(() => generateWith([r"id'$x"]), throwsArgumentError);
    });

    test('emitted summary hides unlisted and nested values', () async {
      final override = generatorWith(['id', 'state', 'type']).generateToStringOverride(
        'Share',
        [
          (key: 'id', field: (type: 'String?', name: 'id')),
          (key: 'state', field: (type: 'enums.ShareState?', name: 'state')),
          (key: 'type', field: (type: 'Child?', name: 'type')),
        ],
        [],
        [],
      );
      final dir = await Directory.systemTemp.createTemp('summary_test');
      addTearDown(() => dir.delete(recursive: true));
      final script = File('${dir.path}/main.dart');
      await script.writeAsString('''
import 'enums.dart' as enums;
class Child {
  String? id = 'CHILD_ID';
  String? seed = 'SEED_SECRET';
}
class Share {
  String? id = 'SHARE_ID';
  enums.ShareState? state = enums.ShareState.active;
  Child? type = Child();
  String? encryptedShare = 'SHARE_SECRET';
$override
}
void main() => print(Share());
''');
      await File('${dir.path}/enums.dart')
          .writeAsString('enum ShareState { active }');

      final run = await Process.run('dart', ['run', script.path]);

      expect(run.stderr, isEmpty);
      expect((run.stdout as String).trim(),
          'Share(id: SHARE_ID, state: active)');
    });
  });
}
