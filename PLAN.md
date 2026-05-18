# Plan: Common interface generation for `oneOf` + `discriminator`

> **Context**: today `swagger_dart_code_generator` ignores the `discriminator`
> of OpenAPI 3 polymorphic wrappers and emits an anti-pattern of N parallel
> nullable fields with no common interface. This forces consumers to write
> manual chains like `wrapper.evm?.x ?? wrapper.solana?.x ?? ...` for every
> common property, and costs us today ~785 lines of `chain_adapter` in
> arnac-mobile that hand-implement what the generator should produce on its own.
>
> This plan introduces **automatic generation of a `sealed class IXxx`** per
> wrapper, with its subtypes doing `implements IXxx`, and a `IXxx? get active`
> getter on the wrapper that points to the currently populated subtype.

---

## Closed decisions

| #   | Decision                                                            | Value                                                                                            |
| --- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| 1   | Which wrappers receive the treatment                                | Every schema with `discriminator.mapping`, ≥ 2 subtypes AND ≥ 1 common prop                      |
| 2   | Transitive type unification                                         | Yes. If a prop's refs are ALL subtypes of another wrapper W, the getter type is `IW`.            |
| 3   | Interface naming                                                    | `I<WrapperName>` (`IVault`, `IEnrichedChain`, ...)                                               |
| 4   | Naming of the getter for the active subtype                         | `active`                                                                                         |
| 5   | Class modifier of the interface                                     | `sealed class` (enables exhaustive pattern matching + `_`/`default:` for forward-compat)         |
| 6   | Lax intersection (props present in ≥ 80% of subtypes)               | Yes. Missing subtypes get a `@override T? get foo => null;` stub                                 |
| 7   | Expose the discriminator as a string on the wrapper                 | **No**. Pattern matching IS the discriminator                                                    |
| 8   | `_active` cached or computed                                        | **Cached** (field set in `fromJson`, not recomputed on access)                                   |
| 9   | `_active` must stay out of `==`/`hashCode`/`copyWith`/`toJson`      | Yes (the existing regex filters it because it isn't `final`)                                     |
| 10  | Support for `separate_models: true`                                 | Out of scope. If enabled, fall back to `abstract interface class`. Follow-up.                    |
| 11  | Emit an `UnknownVault` placeholder for unknown discriminator values | Out of scope. `vault.active` stays `null` if no case matches. Follow-up if a real need shows up. |

---

## Change scale

The current Fordefi BFF spec (`arnac-mobile/swagger/bff-openapi.json`) has
**~250 polymorphic wrappers** with `oneOf + discriminator`. The most relevant:

| Wrapper                                                                      | Subtypes |
| ---------------------------------------------------------------------------- | -------- |
| `Transaction`, `CreateTransactionResponse`, `GetTransactionResponse`, etc.   | 24       |
| `CreateTransactionRequest`, `PredictTransactionRequest`, `PredictedSpotSwap` | 23-24    |
| `WebhookTransactionStatusChangeEvent_event`                                  | 22       |
| `UserAction`                                                                 | 17       |
| `Vault`, `CreateVaultResponse`, `GetVaultResponse`                           | 15       |
| `EnrichedChain`, `EnrichedAddress`, `AssetIdentifier`, `AddressBookContact`  | 12-13    |
| ... ~200 more with 2-7 subtypes                                              |          |

After the automatic filter (≥ 2 subtypes AND ≥ 1 common prop with compatible
types), we estimate ~150-200 wrappers receive an IXxx. The expected diff in
`bff_openapi.swagger.dart` (today 212K lines) grows ~1500-3000 lines, all
additive.

---

## Work phases

### Phase 1 — Generator change

Files touched in `~/projects/swagger_generator/`:

- `lib/src/code_generators/swagger_models_generator.dart` (~+250 lines, ~30
  modified)

Implementation outline:

1. **Data classes** (top-level at the end of the file):
   - `OneOfCommonProp { snakeName, camelName, dartType, isNullable }`
   - `OneOfInterfaceInfo { wrapperName, interfaceName, commonProps, allSubtypeNames }`
   - `OneOfSubtypeMembership { interface, missingProps }`

2. **Private state on `SwaggerModelsGenerator`**:

   ```dart
   Map<String, OneOfInterfaceInfo>? _oneOfWrappers;
   Map<String, List<OneOfSubtypeMembership>>? _oneOfSubtypes;
   ```

3. **Method `_buildOneOfAnalysis(Map<String, SwaggerSchema> classes)`**:
   - Iterates schemas, finds those with a non-empty `discriminator.mapping`
   - For each wrapper:
     - Resolves every subtype via `$ref` → schema
     - Unions `properties` (with `allOf` resolved if applicable)
     - Computes intersection: for every property name, a normalized signature
       (`$ref` or `type+format` or `array<X>`)
     - Threshold: include a property if present in ≥ `ceil(0.8 * count)`
       subtypes AND all occurrences share the same signature
     - Applies transitive: if signatures diverge but every ref is a subtype of
       the same other wrapper W (after the first pass), use `IW` as the unified
       signature
   - Skips wrappers with 1 subtype or 0 common props
   - Populates `_oneOfWrappers` and `_oneOfSubtypes`

4. **Pre-pass call** at the start of `generateBase`, after
   `classes.addAll(classesFromInnerClasses)`.

5. **Method `_generateSealedInterface(OneOfInterfaceInfo info)`** that emits:

   ```dart
   sealed class IVault {
     String? get id;
     DateTime? get createdAt;
     // ... one getter per commonProp, always nullable
   }
   ```

6. **Changes to `generateModelClassString`**:
   - If wrapper (in `_oneOfWrappers`):
     - Prepend `_generateSealedInterface(info)` to the output
     - Modify the class body to add an `IXxx? _active;` private field +
       `IXxx? get active => _active;` public getter
   - If subtype (in `_oneOfSubtypes`):
     - Change the header `class X {` → `class X implements IY {`
     - Append `@override T? get foo => null;` for each `missingProp` before the
       final `}`

7. **Change to `generatedFromJson`** (only when `hasMapping`):
   - Each switch case appends `<varName>._active = <varName>.<subfield>;` after
     parsing the subtype

### Phase 2 — Generator unit tests

In the fork's `test/`, small controlled fixtures:

- **`oneof_strict_intersection_test.dart`**: schema with 3 subtypes sharing 2
  props with identical types. Verifies IXxx with 2 getters + `implements` on the
  3 subtypes.
- **`oneof_lax_intersection_test.dart`**: 3 subtypes, one prop only in 2 of
  the 3. Verifies it enters IXxx as nullable and the missing subtype gets a
  `@override T? get foo => null;` stub.
- **`oneof_transitive_test.dart`**: two wrappers `Outer` and `Inner`; subtypes
  of `Outer` have a prop pointing to subtypes of `Inner`. Verifies that `IOuter`
  gets `IInner? get prop`.
- **`oneof_skip_test.dart`**: wrapper with 1 subtype (skip), wrapper with 0
  common props (skip).
- **`oneof_type_enum_per_subtype_test.dart`**: real Vault case — each subtype
  has `type` with a unique enum. Verifies `type` does NOT enter IXxx.

Run with `dart test` from `~/projects/swagger_generator`.

### Phase 3 — Validation against the real schema

Without committing changes to arnac-mobile:

1. Temporarily edit `arnac-mobile/pubspec.yaml:135-138`:
   ```yaml
   swagger_dart_code_generator:
     path: /Users/davidfaerman/projects/swagger_generator
   ```
2. **David runs** from the main worktree (I can't run it myself):
   ```bash
   arnac-mobile/scripts/build.sh
   ```
3. Compare `lib/core/network/rest/swagger/bff_openapi.swagger.dart`
   before/after.

**Diff acceptance criteria**:

- Purely additive diff. `git diff --stat` shows only line additions, no
  deletions.
- Expected (bounded) non-additive changes: class headers like `class EvmVault {`
  → `class EvmVault implements IVault {` (one inline word added).
- If lines are deleted anywhere else: **bug**, I stop and debug.

### Phase 4 — arnac-mobile compile check

With the regenerated output:

```bash
arnac-mobile/scripts/analyze.sh
```

Must pass cleanly. This proves: zero existing call-sites break. All code that
today does `vault.evm?.X`, `chain.solana?.Y`, `addr.cosmos?.Z` still compiles.

```bash
arnac-mobile/scripts/test-flutter.sh
```

Existing tests touching Vault/Chain/Address/AssetIdentifier must stay green.

If anything breaks here, I stop and surface the error.

### Phase 5 — PR to the fork + bump in arnac-mobile

If Phase 4 passes:

1. Commit on the fork's `oneof-common-interface` branch → push to
   `arnac-io/swagger-dart-code-generator`
2. PR against `fordefi_master` with a link to this plan
3. Once merged: bump the `ref:` in `arnac-mobile/pubspec.yaml`
4. `arnac-mobile/scripts/pub-get.sh` to pin the lockfile
5. PR in arnac-mobile that ships **only** the ref bump + regenerated output.

### Phase 6 (separate PR, optional) — `chain_adapter` cleanup

Take advantage of the new API in arnac-mobile:

- Replace `chainVaultFrom(v)` with `v.active` directly
- Replace `??` chains with `wrapper.active?.X`
- Delete obsolete interfaces (`ChainInfo`, `ChainAssetId`, `ChainVault`,
  `ChainAddress`) if they end up empty post-migration, or shrink them to just
  the members the wrapper doesn't provide
- Delete `chain_adapter/factories.dart`

Expected: 785 lines → ~200 lines.

---

## How the code is used afterwards

### Common field access

```dart
// TODAY:
final name = vault.evm?.name
    ?? vault.solana?.name
    ?? vault.cosmos?.name
    ?? /* ... 12 more */;

// AFTER:
final name = vault.active?.name;
```

### Exhaustive pattern matching

```dart
// TODAY: 15-way if/else, no compile-time guarantee
String describeVault(Vault v) {
  if (v.evm != null) return 'EVM: ${v.evm!.address}';
  if (v.solana != null) return 'Solana: ${v.solana!.address}';
  // ...
  return 'unknown';
}

// AFTER: switch over a sealed type, compile-time exhaustive
String describeVault(Vault v) => switch (v.active) {
  EvmVault(:final address)    => 'EVM: $address',
  SolanaVault(:final address) => 'Solana: $address',
  // ... the compiler breaks the build if a case is missing
  null                        => 'unknown',
};
```

### Pattern matching with forward-compat

```dart
// "I don't care about each chain, just group them":
final label = switch (vault.active) {
  EvmVault()    => 'EVM',
  SolanaVault() => 'Solana',
  _             => 'other',     // ← new chains fall here, no break
};
```

### Generic functions accepting any vault

```dart
void displayVault(IVault vault) {
  print('${vault.name} (id: ${vault.id}, created: ${vault.createdAt})');
}

// Calls:
displayVault(vault.evm!);      // OK, EvmVault implements IVault
displayVault(vault.active!);   // OK, active is IVault?
```

### Transitive: AssetIdentifier.chain ⇒ IEnrichedChain

```dart
// TODAY:
final chainName = assetId.evm?.chain.name
    ?? assetId.solana?.chain.name
    ?? assetId.cosmos?.chain.name
    ?? /* ... 10 more */;

// AFTER:
final chainName = assetId.active?.chain?.name;
//                                ^^^^^^^
//                                IEnrichedChain? via transitive unification
```

### Identity preserved (no re-allocation)

```dart
final a = vault.active;
final b = vault.active;
identical(a, b);  // true — same object returned every time
a == b;           // true
```

This avoids spurious rebuilds in Flutter when `vault` doesn't change.

---

## Validation

### Level 1 — Generator unit tests

Output: `dart test` in the fork.

Covers: the 5 fixtures from Phase 2. Fails fast if intersection, transitive, or
stub-emission logic breaks.

### Level 2 — Manual diff of the regenerated output

```bash
# After regen:
git -C /Users/davidfaerman/projects/arnac diff arnac-mobile/lib/core/network/rest/swagger/bff_openapi.swagger.dart \
  | grep '^-[^-]'
# Should be empty except for class header lines `class X {` modified to `class X implements IY {`
```

If grep shows anything else deleted → bug.

### Level 3 — Static analyzer

```bash
arnac-mobile/scripts/analyze.sh
```

Must finish with zero errors. Proves: backward compatibility of call-sites.

### Level 4 — Existing Flutter suite

```bash
arnac-mobile/scripts/test-flutter.sh
```

Zero regressions in tests touching the 4 main wrappers (Vault, EnrichedChain,
EnrichedAddress, AssetIdentifier).

### Level 5 — Smoke test of the new API

Ad-hoc post-regen test:

```dart
test('Vault.active works for EVM', () {
  final json = jsonDecode(evmVaultFixtureJson);
  final v = Vault.fromJson(json);

  expect(v.evm, isNotNull);                 // legacy path
  expect(v.active, isNotNull);              // new path
  expect(v.active, isA<EvmVault>());         // sealed/pattern compat
  expect(v.active?.id, v.evm?.id);           // getter equivalence
  expect(identical(v.active, v.evm), true);  // identity preserved
});

test('Vault.active null for unknown discriminator', () {
  final json = {'type': 'monad', /* fields */};
  final v = Vault.fromJson(json);

  expect(v.active, isNull);     // graceful unknown
});
```

### Level 6 — adapter ↔ active equivalence (during Phase 6)

Before deleting `chainVaultFrom`, a test that, for every real chain:

```dart
test('chainVaultFrom matches vault.active for $chain', () {
  final v = parseRealVaultJson(chain);
  expect(chainVaultFrom(v)?.name, v.active?.name);
  expect(chainVaultFrom(v)?.id, v.active?.id);
  // ... etc for the ~14 common fields
});
```

If all 15 chains pass → safe to delete `chainVaultFrom`.

---

## Review checkpoints

I'll stop and check in at these moments:

1. **After Phase 1**: I show the fork diff before pushing.
2. **After Phase 3 (bff_openapi.swagger.dart diff)**: we walk the diff together
   before declaring success.
3. **If Phase 4 fails on analyze/test**: I stop, show the error, debug together.
4. **Before Phase 5 (PR to fork)**: you confirm the PR should go out.

---

## Identified risks

| Risk                                                                        | Mitigation                                                                                                                                                                 |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Bug in signature comparison across subtypes → mistyped IXxx                 | Unit tests covering refs, primitives with format, arrays                                                                                                                   |
| Huge `bff_openapi.swagger.dart` diff alarms the manager                     | Diff is 100% additive; verifiable with `grep '^-[^-]'`. If needed, I can do a selective mode (only Vault/Chain/Address/AssetIdentifier) controllable via `build.yaml`      |
| Name collision (subtype with a field named `active`)                        | Pre-pass detects and reports. If it happens, use `$active` or vary the getter name via an option                                                                           |
| Performance: `fromJson` switch gets an extra `vault._active = ...` per case | Trivial — one pointer per parse, O(1), doesn't affect hot paths                                                                                                            |
| `separate_models: true` enabled in the future                               | Out of scope. The generator would emit a sealed class with subtypes in other files → compile error. Follow-up: detect the flag and fall back to `abstract interface class` |
| BE adds a new chain and a `_`-less switch breaks the mobile build           | **Desired behavior** of sealed types: it warns you to handle it. If you want graceful, write `_ => ...` in the switch from day one                                         |

---

## Not in scope

- Refactor of `chain_adapter` and call-sites in arnac-mobile (Phase 6, separate
  PR).
- Generation of an `UnknownVault` placeholder (follow-up if needed).
- Support for `separate_models: true` (follow-up).
- Configuration via `build.yaml` of the lax threshold (80%) or the `I` prefix
  (follow-up).
- Migration to OpenAPI Generator + Dio (separate project, blocked by manager
  today).
