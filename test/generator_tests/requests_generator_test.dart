import 'package:swagger_dart_code_generator/src/code_generators/swagger_requests_generator.dart';
import 'package:swagger_dart_code_generator/src/models/generator_options.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/swagger_root.dart';
import 'package:test/test.dart';

import 'test_data.dart';

void main() {
  group('Requests generator tests', () {
    final root = SwaggerRoot.parse(carsService);

    test('Should generate CarsApi', () {
      final result = SwaggerRequestsGenerator(GeneratorOptions(
        inputFolder: '',
        outputFolder: '',
        ignoreHeaders: true,
        responseOverrideValueMap: [
          ResponseOverrideValueMap(
            method: 'get',
            url: '/cars/schemaRefBody',
            overriddenValue: 'String',
          ),
          ResponseOverrideValueMap(
            method: '',
            url: '/cars/returnTypeTests',
            overriddenValue: 'int',
          ),
        ],
      )).generate(
        swaggerRoot: root,
        className: 'CarsService',
        fileName: 'cars_service',
        allEnums: [],
      );

      final result2 = SwaggerRequestsGenerator(GeneratorOptions(
          inputFolder: '',
          outputFolder: '',
          defaultHeaderValuesMap: [
            DefaultHeaderValueMap(
              defaultValue: '120',
              headerName: 'id',
            ),
          ],
          includePaths: [
            'car'
          ])).generate(
        swaggerRoot: root,
        allEnums: [],
        className: 'CarsService',
        fileName: 'cars_service',
      );

      expect(result2, contains('Future<chopper.Response<CarModel>>'));
      expect(result, contains('Future<chopper.Response<String>> carsSchemaRefBodyGet'));
      expect(result, contains('Future<chopper.Response<CarModel>> carsSchemaRefBodyPost'));
      expect(result, contains('Future<chopper.Response<int>> carsReturnTypeTestsGet'));
      expect(result, contains('Future<chopper.Response<int>> carsReturnTypeTestsPost'));
      expect(result, contains('Future<chopper.Response<int>> carsReturnTypeTestsPut'));
      expect(result, contains('Future<chopper.Response<CarModel>> carsGet'));
      expect(result, contains('Future<chopper.Response<CarModel>> carsPost'));
      expect(result,
          contains('Future<chopper.Response<CarModel>> carsMultipartPost'));
    });

    String generateCarsService() => SwaggerRequestsGenerator(GeneratorOptions(
          inputFolder: '',
          outputFolder: '',
        )).generate(
          swaggerRoot: root,
          className: 'CarsService',
          fileName: 'cars_service',
          allEnums: [],
        );

    String withoutWhitespace(String code) => code.replaceAll(RegExp(r'\s'), '');

    test('create() requires baseUrl and has no spec-host fallback', () {
      final code = withoutWhitespace(generateCarsService());

      expect(code, contains('requiredUribaseUrl'));
      expect(code, contains('baseUrl:baseUrl'));
      expect(code, isNot(contains('baseUrl??')));
    });

    test('create() sets the reporter only when one is passed', () {
      final code = withoutWhitespace(generateCarsService());

      expect(code,
          contains('if(reporter!=null){SwaggerReporterHelper.setReporter(reporter);}'));
      expect('setReporter('.allMatches(code), hasLength(1));
      expect(code.indexOf('setReporter(reporter)'),
          lessThan(code.indexOf('if(client!=null)')));
    });
  });
}
