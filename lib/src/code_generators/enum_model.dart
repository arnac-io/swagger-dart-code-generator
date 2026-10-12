import 'package:recase/recase.dart';
import 'package:swagger_dart_code_generator/src/exception_words.dart';
import 'package:swagger_dart_code_generator/src/extensions/string_extension.dart';

class EnumModel {
  final String name;
  final List<String> values;
  final bool isInteger;
  final List<String> enumNames;

  static const String defaultEnumFieldName = 'value_';

  const EnumModel({
    required this.name,
    required this.values,
    required this.isInteger,
    required this.enumNames,
  });

  @override
  String toString() => _getEnumContent();

  static String _normalizeJsonKeyString(String jsonKey) {
    return jsonKey.replaceAll("\$", "\\\$").replaceAll('\'', '\\\'');
  }

  String _getEnumContent() {
    final resultStrings = <String>[];

    final allFieldNames = <String>[];

    for (int i = 0; i < values.length; i++) {
      final value = values[i];

      var validatedValue = enumNames.isNotEmpty ? enumNames[i] : value;

      validatedValue = getValidatedEnumFieldName(
        validatedValue,
        value,
        isInteger,
        allFieldNames,
      );

      allFieldNames
          .add(validatedValue.substring(0, validatedValue.indexOf('(')));

      if (isInteger) {
        resultStrings.add(
            "\t@JsonValue(${_normalizeJsonKeyString(value)})\n\t$validatedValue");
      } else {
        resultStrings.add(
            "\t@JsonValue('${_normalizeJsonKeyString(value)}')\n\t$validatedValue");
      }
    }

    return '''
enum $name {
@JsonValue(null)
swaggerGeneratedUnknown(null),

${resultStrings.join(',\n')};

final ${isInteger ? 'int' : 'String'}? value;

const $name(this.value);
}''';
  }

  static String getValidatedEnumFieldName(
    String fieldName,
    String fieldValue,
    bool isInteger,
    List<String> allFieldNames,
  ) {
    if (fieldName.isEmpty) {
      fieldName = 'null';
    }

    var result = fieldName
        .replaceAll(RegExp(r'[^\w|\_|)]'), '_')
        .split('_')
        .where((element) => element.isNotEmpty)
        .map((String word) => word.toLowerCase().capitalize)
        .join();

    if (result.startsWith(RegExp('[0-9]+'))) {
      result = defaultEnumFieldName + result;
    }

    result = result.lower;

    if (exceptionWords.contains(result)) {
      result = '\$$result';
    }

    if (result == 'value') {
      result = 'enumValue';
    }

    if (result.isEmpty) {
      result = 'undefined';
    }

    while (allFieldNames.contains(result.lower)) {
      result = '\$$result';
    }

    if (result == 'value') {
      result = 'enumValue';
    }

    return '$result(${isInteger ? fieldValue : '\'${_normalizeJsonKeyString(fieldValue)}\''})';
  }

  /// The helpers of [enums] that [code] calls, directly or through another helper.
  static String referencedHelpers(
    List<EnumModel> enums,
    String code, [
    bool caseSensitive = true,
  ]) {
    final helpers = {
      for (final e in enums) ...e.generateHelpers(caseSensitive),
    };
    final identifier = RegExp(r'[\w$]+');
    final used = <String>{};
    final pending = [code];
    while (pending.isNotEmpty) {
      for (final match in identifier.allMatches(pending.removeLast())) {
        final name = match[0]!;
        if (helpers.containsKey(name) && used.add(name)) {
          pending.add(helpers[name]!);
        }
      }
    }
    return helpers.entries
        .where((e) => used.contains(e.key))
        .map((e) => e.value)
        .join('\n');
  }

  /// The top-level (de)serialization helpers for this enum, keyed by function name.
  Map<String, String> generateHelpers([bool caseSensitive = true]) {
    final type = isInteger ? 'int' : 'String';
    final n = name.camelCase;

    String enumParse(bool nullCheck) => caseSensitive
        ? 'return enums.$name.values.firstWhereOrNull((e) => e.value == $n) ?? defaultValue'
        : 'return enums.$name.values.firstWhereOrNull((e) => e.value.toString().toLowerCase() == $n${nullCheck ? '?' : ''}.toString().toLowerCase()) ?? defaultValue';

    return {
      '${n}NullableToJson': '''
$type? ${n}NullableToJson(enums.$name? $n) {
  return $n?.value;
}
''',
      '${n}ToJson': '''
$type? ${n}ToJson(enums.$name $n) {
  return $n.value;
}
''',
      '${n}FromJson': '''
enums.$name ${n}FromJson(
  Object? $n,
  [enums.$name? defaultValue,]
  ) {

${enumParse(true)} ?? enums.$name.swaggerGeneratedUnknown;
}
''',
      '${n}NullableFromJson': '''
enums.$name? ${n}NullableFromJson(
  Object? $n,
  [enums.$name? defaultValue,]
  ) {
    if($n == null){
      return null;
    }
    ${enumParse(false)};
}
''',
      '${n}ExplodedListToJson': '''
String ${n}ExplodedListToJson(
    List<enums.$name>? $n) {

    if ($n == null) {
      return '';
    }
    String sValues = '';
    for (final e in $n!) {
      if (e.value != null) {
        sValues += e.value!.toString() + ',';
      }
    }
    return sValues;
}
''',
      '${n}ListToJson': '''
List<$type> ${n}ListToJson(
    List<enums.$name>? $n) {

  if($n == null)
  {
    return [];
  }

  List<$type> listValues = [];
    for (final e in $n!) {
      if (e.value != null) {
        listValues.add(e.value!);
      }
    }
    return listValues;
}
''',
      '${n}ListFromJson': '''
List<enums.$name> ${n}ListFromJson(
    List? $n,
    [List<enums.$name>? defaultValue,]) {

  if($n == null)
  {
    return defaultValue ?? [];
  }

  return $n
      .map((e) => ${n}FromJson(e.toString()))
      .toList();
}
''',
      '${n}NullableListFromJson': '''
List<enums.$name>? ${n}NullableListFromJson(
    List? $n,
    [List<enums.$name>? defaultValue,]) {

  if($n == null)
  {
    return defaultValue;
  }

  return $n
      .map((e) => ${n}FromJson(e.toString()))
      .toList();
}
''',
    };
  }
}
