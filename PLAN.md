# Plan: Common interface generation para `oneOf` + `discriminator`

> **Contexto**: hoy `swagger_dart_code_generator` ignora el `discriminator` de
> los wrappers polimórficos OpenAPI 3 y emite un anti-patrón de N campos
> nullable paralelos sin interfaz común. Esto fuerza al consumer a escribir
> cadenas manuales `wrapper.evm?.x ?? wrapper.solana?.x ?? ...` para cada
> propiedad común, y nos cuesta hoy ~785 líneas de `chain_adapter` en
> arnac-mobile que reimplementan a mano lo que el generator debería hacer solo.
>
> Este plan introduce **generación automática de un `sealed class IXxx`** por
> wrapper, con sus subtipos haciendo `implements IXxx`, y un getter
> `IXxx? get active` en el wrapper que apunta al subtipo activo.

---

## Decisiones cerradas

| #   | Decisión                                                           | Valor                                                                                                |
| --- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| 1   | Qué wrappers reciben tratamiento                                   | Todo schema con `discriminator.mapping`, ≥ 2 subtipos Y ≥ 1 prop común                               |
| 2   | Transitive type unification                                        | Sí. Si una prop apunta a refs que TODOS son subtipos de otro wrapper W, el tipo del getter es `IW`.  |
| 3   | Naming del interface                                               | `I<WrapperName>` (`IVault`, `IEnrichedChain`, ...)                                                   |
| 4   | Naming del getter al subtipo activo                                | `active`                                                                                             |
| 5   | Modificador de clase del interface                                 | `sealed class` (permite pattern matching exhaustivo + `_`/`default:` para forward-compat)            |
| 6   | Lax intersection (props presentes en ≥ 80% de subtipos)            | Sí. Las que faltan: stub `@override T? get foo => null;` en el subtipo                               |
| 7   | Exponer discriminator como string en el wrapper                    | **No**. Pattern matching ES el discriminador                                                         |
| 8   | `_active` cacheado o computado                                     | **Cacheado** (field set en `fromJson`, no recomputado por acceso)                                    |
| 9   | `_active` debe quedar fuera de `==`/`hashCode`/`copyWith`/`toJson` | Sí (la regex actual lo filtra por no ser `final`)                                                    |
| 10  | Soporte para `separate_models: true`                               | Out of scope. Si alguien lo activa, degradar a `abstract interface class`. Follow-up.                |
| 11  | Emitir `UnknownVault` placeholder para discriminator desconocido   | Out of scope. `vault.active` queda `null` si no matchea ningún case. Follow-up si aparece necesidad. |

---

## Escala del cambio

El spec actual de Fordefi BFF (`arnac-mobile/swagger/bff-openapi.json`) tiene
**~250 wrappers polimórficos** con `oneOf + discriminator`. Los más relevantes:

| Wrapper                                                                      | Subtipos |
| ---------------------------------------------------------------------------- | -------- |
| `Transaction`, `CreateTransactionResponse`, `GetTransactionResponse`, etc.   | 24       |
| `CreateTransactionRequest`, `PredictTransactionRequest`, `PredictedSpotSwap` | 23-24    |
| `WebhookTransactionStatusChangeEvent_event`                                  | 22       |
| `UserAction`                                                                 | 17       |
| `Vault`, `CreateVaultResponse`, `GetVaultResponse`                           | 15       |
| `EnrichedChain`, `EnrichedAddress`, `AssetIdentifier`, `AddressBookContact`  | 12-13    |
| ... ~200 más con 2-7 subtipos                                                |          |

Después del filtro automático (≥ 2 subtipos Y ≥ 1 prop común con tipos
compatibles), estimamos ~150-200 wrappers reciben IXxx. El diff esperado en
`bff_openapi.swagger.dart` (hoy 212K líneas) crece ~1500-3000 líneas, todas
aditivas.

---

## Fases del trabajo

### Fase 1 — Cambio al generator

Archivos a tocar en `~/projects/swagger_generator/`:

- `lib/src/code_generators/swagger_models_generator.dart` (~+250 líneas, ~30
  modificadas)

Estructura de la implementación:

1. **Data classes** (top-level al final del archivo):
   - `OneOfCommonProp { snakeName, camelName, dartType, isNullable }`
   - `OneOfInterfaceInfo { wrapperName, interfaceName, commonProps, allSubtypeNames }`
   - `OneOfSubtypeMembership { interface, missingProps }`

2. **Estado privado en `SwaggerModelsGenerator`**:

   ```dart
   Map<String, OneOfInterfaceInfo>? _oneOfWrappers;
   Map<String, List<OneOfSubtypeMembership>>? _oneOfSubtypes;
   ```

3. **Método `_buildOneOfAnalysis(Map<String, SwaggerSchema> classes)`**:
   - Itera schemas, encuentra los que tienen `discriminator.mapping` no vacío
   - Para cada wrapper:
     - Resuelve cada subtipo via `$ref` → schema
     - Une `properties` (con `allOf` resuelto si aplica)
     - Calcula intersección: por cada property name, signature normalizada
       (`$ref` o `type+format` o `array<X>`)
     - Threshold: incluir property si presente en ≥ `ceil(0.8 * count)` subtipos
       Y todas las apariciones comparten signature
     - Aplica transitive: si signature divergente pero todas las refs son
       subtipos del mismo otro wrapper W (post first-pass), usa `IW` como
       signature unificada
   - Skipea wrappers con 1 subtipo o 0 common props
   - Llena `_oneOfWrappers` y `_oneOfSubtypes`

4. **Llamada al pre-pass** al inicio de `generateBase`, después de
   `classes.addAll(classesFromInnerClasses)`.

5. **Método `_generateSealedInterface(OneOfInterfaceInfo info)`** que emite:

   ```dart
   sealed class IVault {
     String? get id;
     DateTime? get createdAt;
     // ... un getter por commonProp, siempre nullable
   }
   ```

6. **Modificaciones a `generateModelClassString`**:
   - Si es wrapper (en `_oneOfWrappers`):
     - Prepend `_generateSealedInterface(info)` al output
     - Modificar el cuerpo de la clase para agregar `IXxx? _active;` field
       privado + `IXxx? get active => _active;` getter público
   - Si es subtipo (en `_oneOfSubtypes`):
     - Cambiar header `class X {` → `class X implements IY {`
     - Append `@override T? get foo => null;` por cada `missingProp` antes del
       `}` final

7. **Modificación a `generatedFromJson`** (solo cuando `hasMapping`):
   - Cada case del switch agrega `<varName>._active = <varName>.<subfield>;`
     después del parse del subtipo

### Fase 2 — Tests unitarios del generator

En `test/` del fork, fixtures pequeños bajo control:

- **`oneof_strict_intersection_test.dart`**: schema con 3 subtipos que comparten
  2 props con tipos idénticos. Verifica IXxx con 2 getters + `implements` en los
  3 subtipos.
- **`oneof_lax_intersection_test.dart`**: 3 subtipos, una prop solo en 2 de
  los 3. Verifica que entra en IXxx como nullable y el subtipo faltante tiene
  `@override T? get foo => null;` stub.
- **`oneof_transitive_test.dart`**: dos wrappers `Outer` e `Inner`; subtipos de
  `Outer` tienen una prop apuntando a subtipos de `Inner`. Verifica que `IOuter`
  tiene `IInner? get prop`.
- **`oneof_skip_test.dart`**: wrapper con 1 subtipo (skip), wrapper con 0 props
  comunes (skip).
- **`oneof_type_enum_per_subtype_test.dart`**: caso real Vault — cada subtipo
  tiene `type` con enum único. Verifica que `type` no entra en IXxx.

Correr con `dart test` desde `~/projects/swagger_generator`.

### Fase 3 — Validación contra el schema real

Sin commitear cambios a arnac-mobile:

1. Editar local `arnac-mobile/pubspec.yaml:135-138` temporalmente:
   ```yaml
   swagger_dart_code_generator:
     path: /Users/davidfaerman/projects/swagger_generator
   ```
2. **Daisy/David corre** desde main worktree (no puedo correrlo yo):
   ```bash
   arnac-mobile/scripts/build.sh
   ```
3. Comparar `lib/core/network/rest/swagger/bff_openapi.swagger.dart`
   antes/después.

**Criterio de aceptación del diff**:

- Diff puramente aditivo. `git diff --stat` muestra solo adiciones de líneas,
  sin deletions.
- Cambios legítimos no-aditivos esperados (acotados): los headers de clases tipo
  `class EvmVault {` → `class EvmVault implements IVault {` (una palabra
  agregada inline).
- Si hay líneas borradas en cualquier otro lado: **bug**, detengo y debuggeo.

### Fase 4 — Compile check de arnac-mobile

Con el output regenerado:

```bash
arnac-mobile/scripts/analyze.sh
```

Debe pasar limpio. Prueba: cero call-sites existentes rompen. Todo el código de
hoy que hace `vault.evm?.X`, `chain.solana?.Y`, `addr.cosmos?.Z`, sigue
compilando.

```bash
arnac-mobile/scripts/test-flutter.sh
```

Los tests existentes que tocan Vault/Chain/Address/AssetIdentifier deben seguir
verdes.

Si algo rompe acá, paro y muestro el error.

### Fase 5 — PR al fork + bump en arnac-mobile

Si Fase 4 pasa:

1. Commit en branch `oneof-common-interface` del fork → push a
   `arnac-io/swagger-dart-code-generator`
2. PR contra `fordefi_master` con link a este plan
3. Una vez mergeado: bump del `ref:` en `arnac-mobile/pubspec.yaml`
4. `arnac-mobile/scripts/pub-get.sh` para fijar el lockfile
5. PR en arnac-mobile que sube **sólo** el bump del ref + el output regenerado.

### Fase 6 (PR separado, opcional) — Cleanup de `chain_adapter`

Aprovechar la nueva API en arnac-mobile:

- Reemplazar `chainVaultFrom(v)` por `v.active` directo
- Reemplazar cadenas `??` por `wrapper.active?.X`
- Borrar interfaces obsoletas (`ChainInfo`, `ChainAssetId`, `ChainVault`,
  `ChainAddress`) si quedan vacías post-migración, o achicarlas a sólo los
  miembros que el wrapper no provee
- Eliminar `chain_adapter/factories.dart`

Esperado: 785 líneas → ~200 líneas.

---

## Cómo se usa el código después

### Acceso a campos comunes

```dart
// HOY:
final name = vault.evm?.name
    ?? vault.solana?.name
    ?? vault.cosmos?.name
    ?? /* ... 12 más */;

// DESPUÉS:
final name = vault.active?.name;
```

### Pattern matching exhaustivo

```dart
// HOY: 15-way if/else, sin compile-time guarantee
String describeVault(Vault v) {
  if (v.evm != null) return 'EVM: ${v.evm!.address}';
  if (v.solana != null) return 'Solana: ${v.solana!.address}';
  // ...
  return 'unknown';
}

// DESPUÉS: switch sobre sealed, compile-time exhaustive
String describeVault(Vault v) => switch (v.active) {
  EvmVault(:final address)    => 'EVM: $address',
  SolanaVault(:final address) => 'Solana: $address',
  // ... el compilador rompe el build si me falta un caso
  null                        => 'unknown',
};
```

### Pattern matching con forward-compat

```dart
// Caso "no me importa cada chain, sólo agrupo":
final label = switch (vault.active) {
  EvmVault()    => 'EVM',
  SolanaVault() => 'Solana',
  _             => 'other',     // ← nuevas chains caen acá, no rompe
};
```

### Funciones genéricas que aceptan cualquier vault

```dart
void displayVault(IVault vault) {
  print('${vault.name} (id: ${vault.id}, created: ${vault.createdAt})');
}

// Llamadas:
displayVault(vault.evm!);      // OK, EvmVault implements IVault
displayVault(vault.active!);   // OK, active es IVault?
```

### Transitive: AssetIdentifier.chain ⇒ IEnrichedChain

```dart
// HOY:
final chainName = assetId.evm?.chain.name
    ?? assetId.solana?.chain.name
    ?? assetId.cosmos?.chain.name
    ?? /* ... 10 más */;

// DESPUÉS:
final chainName = assetId.active?.chain?.name;
//                                ^^^^^^^
//                                IEnrichedChain? gracias a transitive
```

### Identity preservada (no hay re-alocación)

```dart
final a = vault.active;
final b = vault.active;
identical(a, b);  // true — devuelve el mismo objeto cada vez
a == b;           // true
```

Esto evita rebuilds espurios en Flutter cuando `vault` no cambia.

---

## Validación

### Nivel 1 — Tests unitarios del generator

Output: ` dart test` en el fork.

Cubre: las 5 fixtures de Fase 2. Falla rápido si la lógica de intersección,
transitive, o emisión de stubs rompe.

### Nivel 2 — Diff manual del output regenerado

```bash
# Después de regen:
git -C /Users/davidfaerman/projects/arnac diff arnac-mobile/lib/core/network/rest/swagger/bff_openapi.swagger.dart \
  | grep '^-[^-]'
# Debería estar vacío excepto líneas de header tipo `class X {` modificadas a `class X implements IY {`
```

Si el grep muestra otra cosa borrada → bug.

### Nivel 3 — Static analyzer

```bash
arnac-mobile/scripts/analyze.sh
```

Debe terminar con cero errores. Prueba: backward compatibility de call-sites.

### Nivel 4 — Suite Flutter existente

```bash
arnac-mobile/scripts/test-flutter.sh
```

Cero regresiones en tests que tocan los 4 wrappers principales (Vault,
EnrichedChain, EnrichedAddress, AssetIdentifier).

### Nivel 5 — Smoke test de la nueva API

Test ad-hoc post-regen:

```dart
test('Vault.active works for EVM', () {
  final json = jsonDecode(evmVaultFixtureJson);
  final v = Vault.fromJson(json);

  expect(v.evm, isNotNull);                // legacy path
  expect(v.active, isNotNull);             // new path
  expect(v.active, isA<EvmVault>());        // sealed/pattern compat
  expect(v.active?.id, v.evm?.id);          // getter equivalence
  expect(identical(v.active, v.evm), true); // identity preserved
});

test('Vault.active null para discriminator desconocido', () {
  final json = {'type': 'monad', /* fields */};
  final v = Vault.fromJson(json);

  expect(v.active, isNull);     // graceful unknown
});
```

### Nivel 6 — Equivalencia adapter ↔ active (durante Fase 6)

Antes de borrar `chainVaultFrom`, un test que para cada chain real:

```dart
test('chainVaultFrom matches vault.active for $chain', () {
  final v = parseRealVaultJson(chain);
  expect(chainVaultFrom(v)?.name, v.active?.name);
  expect(chainVaultFrom(v)?.id, v.active?.id);
  // ... etc para los ~14 campos comunes
});
```

Si los 15 chains pasan → safe to delete `chainVaultFrom`.

---

## Checkpoints de revisión

Voy a parar y consultar en estos momentos:

1. **Post Fase 1**: muestro el diff del fork antes de pushearlo.
2. **Post Fase 3 (diff de bff_openapi.swagger.dart)**: pasamos el diff juntos
   antes de declarar éxito.
3. **Si Fase 4 falla en analyze/test**: paro, muestro el error, debuggeamos
   juntos.
4. **Antes de Fase 5 (PR al fork)**: confirmás que el PR vaya.

---

## Riesgos identificados

| Riesgo                                                                       | Mitigación                                                                                                                                                                |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Bug en signature comparison entre subtipos → IXxx mal tipado                 | Tests unitarios cubriendo refs, primitivos con format, arrays                                                                                                             |
| Diff de `bff_openapi.swagger.dart` enorme alarma al manager                  | Diff es 100% aditivo; verificable con `grep '^-[^-]'`. Si necesita, puedo hacer un modo selectivo (sólo Vault/Chain/Address/AssetIdentifier) controlable via `build.yaml` |
| Colisión de nombres (subtipo con field `active`)                             | Pre-pass detecta y reporta. Si pasa, usar `$active` o variar el getter name vía option                                                                                    |
| Performance: switch del fromJson recibe `vault._active = ...` extra por case | Trivial — un puntero por parse, O(1), no afecta hot paths                                                                                                                 |
| `separate_models: true` activado en el futuro                                | Fuera de scope. El generator emitiría sealed con subtipos en otros archivos → compile error. Follow-up: detectar la flag y degradar a `abstract interface class`          |
| BE agrega un chain nuevo y un switch sin `_` rompe el build de mobile        | **Comportamiento deseado** del sealed: te avisa que hay que manejarlo. Si querés graceful, escribís `_ => ...` en el switch desde el inicio                               |

---

## No incluido en este scope

- Refactor de `chain_adapter` y call-sites en arnac-mobile (Fase 6, PR
  separado).
- Generación de `UnknownVault` placeholder (follow-up si aparece).
- Soporte para `separate_models: true` (follow-up).
- Configuración via `build.yaml` del threshold lax (80%) o del prefix `I`
  (follow-up).
- Migración a OpenAPI Generator + Dio (proyecto separado, bloqueado por manager
  hoy).
