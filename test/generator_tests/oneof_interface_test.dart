// Tests for the `oneOf` + `discriminator` interface generation:
//   • `sealed class IXxx` emission alongside the wrapper class
//   • `implements IXxx` injection on each subtype
//   • `_active` field + `active` getter on the wrapper
//   • `@override T? get foo => null;` stubs in subtypes missing a lax-common prop
//   • Transitive type unification (one wrapper's subtype implementing another wrapper's interface)
//   • Edge cases: 1-subtype wrapper, 0-common-prop wrapper, enum-divergence rejection

import 'package:swagger_dart_code_generator/src/code_generators/swagger_models_generator.dart';
import 'package:swagger_dart_code_generator/src/code_generators/v3/swagger_models_generator_v3.dart';
import 'package:swagger_dart_code_generator/src/models/generator_options.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/responses/swagger_schema.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/swagger_components.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/swagger_info.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/swagger_root.dart';
import 'package:test/test.dart';

// ─── fixture helpers ────────────────────────────────────────────────────────

SwaggerRoot _root(Map<String, SwaggerSchema> schemas) => SwaggerRoot(
      openapiVersion: '3.0.0',
      basePath: '',
      components: SwaggerComponents(
        parameters: {},
        schemas: schemas,
        responses: {},
        requestBodies: {},
      ),
      info: SwaggerInfo(title: 'test', version: '1'),
      host: '',
      paths: {},
      tags: [],
      schemes: [],
      parameters: {},
      definitions: {},
      securityDefinitions: {},
    );

SwaggerSchema _wrapper({
  required String propertyName,
  required Map<String, String> mapping,
}) =>
    SwaggerSchema(
      oneOf: mapping.values
          .map((ref) => SwaggerSchema(ref: ref))
          .toList(),
      discriminator: Discriminator(
        propertyName: propertyName,
        mapping: mapping,
      ),
    );

SwaggerSchema _string({String format = ''}) =>
    SwaggerSchema(type: 'string', format: format);
SwaggerSchema _bool() => SwaggerSchema(type: 'boolean');
SwaggerSchema _ref(String name) =>
    SwaggerSchema(ref: '#/components/schemas/$name');

SwaggerSchema _objectWithProps(Map<String, SwaggerSchema> properties) =>
    SwaggerSchema(type: 'object', properties: properties);

SwaggerModelsGenerator _gen({bool overrideEquals = false}) =>
    SwaggerModelsGeneratorV3(GeneratorOptions(
      inputFolder: '',
      outputFolder: '',
      overrideEqualsAndHashcode: overrideEquals,
    ));

String _runGenerate(Map<String, SwaggerSchema> schemas) {
  final generator = _gen();
  return generator.generateBase(
    root: _root(schemas),
    fileName: 'test',
    classes: Map.of(schemas),
    allEnums: [],
    generateEnumsMethods: false,
  );
}

// ─── tests ───────────────────────────────────────────────────────────────────

void main() {
  group('strict intersection', () {
    test('emits sealed IXxx, implements on subtypes, _active in wrapper', () {
      final schemas = <String, SwaggerSchema>{
        'EvmFoo': _objectWithProps({
          'id': _string(),
          'name': _string(),
          'evm_only': _bool(),
        }),
        'SolanaFoo': _objectWithProps({
          'id': _string(),
          'name': _string(),
          'solana_only': _bool(),
        }),
        'Foo': _wrapper(
          propertyName: 'type',
          mapping: {
            'evm': '#/components/schemas/EvmFoo',
            'solana': '#/components/schemas/SolanaFoo',
          },
        ),
      };

      final out = _runGenerate(schemas);

      // Sealed interface block exists with the two strict-common getters.
      expect(out, contains('sealed class IFoo {'));
      expect(out, contains('String? get id;'));
      expect(out, contains('String? get name;'));
      // No EVM/Solana-only props leak into the interface.
      expect(out, isNot(contains('get evmOnly;')));
      expect(out, isNot(contains('get solanaOnly;')));

      // Each subtype declares `implements IFoo`.
      expect(out, contains('class EvmFoo implements IFoo{'));
      expect(out, contains('class SolanaFoo implements IFoo{'));

      // Wrapper exposes `_active` field + `active` getter.
      expect(out, contains('IFoo? _active;'));
      expect(out, contains('IFoo? get active => _active;'));

      // fromJson switch sets _active for each case.
      expect(out, contains("case 'evm':"));
      expect(out, contains('foo._active = foo.evm;'));
      expect(out, contains('foo._active = foo.solana;'));
    });
  });

  group('lax intersection', () {
    test('prop missing in 1 of 3 subtypes becomes nullable + null stub', () {
      final schemas = <String, SwaggerSchema>{
        'A': _objectWithProps({
          'id': _string(),
          'shared': _string(),
        }),
        'B': _objectWithProps({
          'id': _string(),
          'shared': _string(),
        }),
        'C': _objectWithProps({
          'id': _string(),
          'shared': _string(),
        }),
        'D': _objectWithProps({
          'id': _string(),
          'shared': _string(),
        }),
        'E': _objectWithProps({
          'id': _string(),
          // 'shared' missing — present in 4 of 5 = 80% threshold met
        }),
        'Container': _wrapper(
          propertyName: 'type',
          mapping: {
            'a': '#/components/schemas/A',
            'b': '#/components/schemas/B',
            'c': '#/components/schemas/C',
            'd': '#/components/schemas/D',
            'e': '#/components/schemas/E',
          },
        ),
      };

      final out = _runGenerate(schemas);

      // Interface includes the lax-common prop.
      expect(out, contains('sealed class IContainer {'));
      expect(out, contains('String? get shared;'));

      // E (the one missing 'shared') has the override stub.
      // A/B/C/D do NOT need stubs because their declared fields satisfy
      // the interface contract covariantly.
      final eClassRegion = _extractClass(out, 'E');
      expect(eClassRegion, contains('@override String? get shared => null;'));

      final aClassRegion = _extractClass(out, 'A');
      expect(aClassRegion,
          isNot(contains('@override String? get shared => null;')));
    });
  });

  group('transitive type unification', () {
    test('subtype-of-A inside B-subtype becomes IA in IB getter', () {
      final schemas = <String, SwaggerSchema>{
        // Wrapper A and its subtypes (so IA is generated).
        'EvmA': _objectWithProps({
          'name': _string(),
        }),
        'SolanaA': _objectWithProps({
          'name': _string(),
        }),
        'A': _wrapper(
          propertyName: 'type',
          mapping: {
            'evm': '#/components/schemas/EvmA',
            'solana': '#/components/schemas/SolanaA',
          },
        ),

        // Wrapper B: each subtype has `inner` that points to a SUBTYPE of A.
        // Since signatures differ (EvmA vs SolanaA), strict rejects.
        // Transitive: both refs are subtypes of A → IB.inner becomes IA?
        'EvmB': _objectWithProps({
          'inner': _ref('EvmA'),
        }),
        'SolanaB': _objectWithProps({
          'inner': _ref('SolanaA'),
        }),
        'B': _wrapper(
          propertyName: 'type',
          mapping: {
            'evm': '#/components/schemas/EvmB',
            'solana': '#/components/schemas/SolanaB',
          },
        ),
      };

      final out = _runGenerate(schemas);

      expect(out, contains('sealed class IA {'));
      expect(out, contains('sealed class IB {'));
      expect(out, contains('IA? get inner;'),
          reason:
              'B subtypes\' `inner` points to refs that are all subtypes of A; transitive should expose IA');
    });
  });

  group('edge cases', () {
    test('wrapper with 1 subtype: no IXxx emitted', () {
      final schemas = <String, SwaggerSchema>{
        'Only': _objectWithProps({
          'x': _string(),
        }),
        'Wrap': _wrapper(
          propertyName: 'type',
          mapping: {'only': '#/components/schemas/Only'},
        ),
      };
      final out = _runGenerate(schemas);
      expect(out, isNot(contains('sealed class IWrap')));
      expect(out, isNot(contains('IWrap? _active;')));
      // Subtype is not decorated.
      expect(out, contains('class Only{'));
      expect(out, isNot(contains('class Only implements')));
    });

    test('wrapper with 0 common props: no IXxx emitted', () {
      final schemas = <String, SwaggerSchema>{
        'X1': _objectWithProps({
          'only_a': _string(),
        }),
        'X2': _objectWithProps({
          'only_b': _bool(),
        }),
        'X': _wrapper(
          propertyName: 'type',
          mapping: {
            'one': '#/components/schemas/X1',
            'two': '#/components/schemas/X2',
          },
        ),
      };
      final out = _runGenerate(schemas);
      expect(out, isNot(contains('sealed class IX ')));
      expect(out, isNot(contains('IX? _active;')));
    });

    test('property with divergent enum refs per subtype is rejected', () {
      // Each subtype's `type` is a $ref to a chain-specific enum schema —
      // strict comparison rejects because the $refs themselves differ.
      final schemas = <String, SwaggerSchema>{
        'EvmTypeGen': SwaggerSchema(type: 'string', enumValuesObj: ['evm']),
        'SolanaTypeGen':
            SwaggerSchema(type: 'string', enumValuesObj: ['solana']),
        'EvmW': _objectWithProps({
          'id': _string(),
          'type': _ref('EvmTypeGen'),
        }),
        'SolanaW': _objectWithProps({
          'id': _string(),
          'type': _ref('SolanaTypeGen'),
        }),
        'W': _wrapper(
          propertyName: 'type',
          mapping: {
            'evm': '#/components/schemas/EvmW',
            'solana': '#/components/schemas/SolanaW',
          },
        ),
      };
      final out = _runGenerate(schemas);
      expect(out, contains('sealed class IW {'));
      expect(out, contains('String? get id;'));
      // `type` must NOT enter the interface — types diverge.
      expect(out, isNot(contains('get type;')));
    });

    test('property with INLINE enum per subtype is rejected (Fordefi pattern)',
        () {
      // The real BFF spec for Vault declares `type` inline in each subtype:
      //   "type": { "type": "string", "enum": ["evm"] }    (in EvmVault)
      //   "type": { "type": "string", "enum": ["solana"] } (in SolanaVault)
      // Raw signatures match (both are `string:`), so a naive intersection
      // would put `String? get type` into the interface. BUT the generator
      // materializes inline enums as per-class types (`EvmVaultTypeGenerated`,
      // `SolanaVaultTypeGenerated`) — meaning the subtype field types diverge
      // even though the raw schemas look identical. Must be rejected.
      final schemas = <String, SwaggerSchema>{
        'EvmInlineW': _objectWithProps({
          'id': _string(),
          'type': SwaggerSchema(type: 'string', enumValuesObj: ['evm']),
        }),
        'SolanaInlineW': _objectWithProps({
          'id': _string(),
          'type': SwaggerSchema(type: 'string', enumValuesObj: ['solana']),
        }),
        'InlineW': _wrapper(
          propertyName: 'type',
          mapping: {
            'evm': '#/components/schemas/EvmInlineW',
            'solana': '#/components/schemas/SolanaInlineW',
          },
        ),
      };
      final out = _runGenerate(schemas);
      expect(out, contains('sealed class IInlineW {'));
      expect(out, contains('String? get id;'));
      expect(out, isNot(contains('get type;')),
          reason: 'Inline enums diverge in the generated Dart layer even when '
              'the raw schema signature matches; must be excluded.');
    });
  });

  group('regressions caught in first regen', () {
    test('subtype referenced from multiple discriminator keys: implements emitted once',
        () {
      // Real-world pattern (BytesArgumentPayload): the same payload class
      // is mapped from multiple discriminator values (`equal`, `not_equal`).
      // The implements clause must NOT emit `implements IFoo, IFoo`.
      final schemas = <String, SwaggerSchema>{
        'PayloadA': _objectWithProps({
          'id': _string(),
          'shared': _string(),
        }),
        'PayloadB': _objectWithProps({
          'id': _string(),
          'shared': _string(),
        }),
        'DualKeyWrap': _wrapper(
          propertyName: 'op',
          mapping: {
            'eq': '#/components/schemas/PayloadA',
            'neq': '#/components/schemas/PayloadA', // same class, second key
            'gt': '#/components/schemas/PayloadB',
          },
        ),
      };
      final out = _runGenerate(schemas);
      // PayloadA appears under two keys: the implements clause must be
      // deduped, otherwise `dart analyze` rejects with implements_repeated.
      expect(out, contains('class PayloadA implements IDualKeyWrap{'));
      expect(
          out,
          isNot(contains(
              'class PayloadA implements IDualKeyWrap, IDualKeyWrap')));
    });

    test('properties listed in options.ignoredKeys are skipped from the interface',
        () {
      final schemas = <String, SwaggerSchema>{
        'IgA': _objectWithProps({
          'id': _string(),
          'metadata_uri': _string(),
        }),
        'IgB': _objectWithProps({
          'id': _string(),
          'metadata_uri': _string(),
        }),
        'IgWrap': _wrapper(
          propertyName: 'type',
          mapping: {
            'a': '#/components/schemas/IgA',
            'b': '#/components/schemas/IgB',
          },
        ),
      };
      final generator =
          SwaggerModelsGeneratorV3(GeneratorOptions(
        inputFolder: '',
        outputFolder: '',
        ignoredKeys: ['metadata_uri', 'metadataUri'],
      ));
      final out = generator.generateBase(
        root: _root(schemas),
        fileName: 'test',
        classes: Map.of(schemas),
        allEnums: [],
        generateEnumsMethods: false,
      );

      expect(out, contains('sealed class IIgWrap {'));
      expect(out, contains('String? get id;'));
      // The ignored field must NOT enter the interface.
      expect(out, isNot(contains('get metadataUri;')));
    });
  });

  group('wrapper extras placement', () {
    test('_active field and active getter live inside the wrapper class', () {
      final schemas = <String, SwaggerSchema>{
        'Aa': _objectWithProps({'id': _string()}),
        'Bb': _objectWithProps({'id': _string()}),
        'W2': _wrapper(
          propertyName: 'type',
          mapping: {
            'a': '#/components/schemas/Aa',
            'b': '#/components/schemas/Bb',
          },
        ),
      };
      final out = _runGenerate(schemas);
      final wrapperRegion = _extractClass(out, 'W2');
      expect(wrapperRegion, contains('IW2? _active;'));
      expect(wrapperRegion, contains('IW2? get active => _active;'));
    });
  });
}

// ─── helpers ────────────────────────────────────────────────────────────────

/// Extracts the textual region of a generated class so we can assert that
/// certain code is INSIDE a particular class (not just somewhere in the file).
/// Returns the substring from `class <name>` up to the matching closing
/// brace of that class.
String _extractClass(String output, String className) {
  final marker = RegExp('class\\s+$className(\\s+implements[^{]*)?\\s*\\{');
  final match = marker.firstMatch(output);
  if (match == null) {
    throw StateError(
        'class $className not found in generated output:\n${output.substring(0, output.length.clamp(0, 500))}');
  }
  // Walk forward, counting braces, until we close the class.
  var depth = 1;
  var i = match.end;
  while (i < output.length && depth > 0) {
    final c = output[i];
    if (c == '{') depth++;
    if (c == '}') depth--;
    i++;
  }
  return output.substring(match.start, i);
}
