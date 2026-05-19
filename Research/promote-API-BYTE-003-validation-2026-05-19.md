# Validation receipt: [API-BYTE-003]
Date: 2026-05-19
Rule: binary serializable uint8 witness
Placement tier: institute
Pack: Institute Linter Rule Byte
Source: `swift-foundations/swift-institute-linter-rules/Sources/Institute Linter Rule Byte/Lint.Rule.Byte.BinarySerializableUInt8Witness.swift`

## Validation ladder (regex pre-scan)

Pattern: `grep -rE 'Buffer\.Element == UInt8|Source\.Element == UInt8|Bytes\.Element == UInt8' Sources/`

| Level | Package | Diagnostic count | Notes |
|-------|---------|------------------|-------|
| Simple | swift-tagged-primitives | 0 | clean |
| Simple | swift-carrier-primitives | 0 | clean |
| Simple | swift-pair-primitives | 0 | clean |
| Medium | swift-property-primitives | 0 | clean |
| Medium | swift-cardinal-primitives | 0 | clean |
| Hard | swift-affine-primitives | 0 | clean |
| Hard | swift-ordinal-primitives | 0 | clean |

## Ground-truth probe (work prioritization input for downstream sweep arc)

Regex upper-bound (AST fire count will be lower after `@_disfavoredOverload` exemption):

| Package | R3 regex upper bound |
|---------|---------------------:|
| swift-iso-32000 | **73** |
| swift-rfc-4648 | **52** |
| swift-ascii-primitives | **15** |
| swift-rfc-9293 | **13** |
| swift-incits-4-1986 | **6** |
| swift-binary-primitives | 3 |
| swift-rfc-7519 | 1 |
| swift-foundations/swift-ascii | 1 |
| swift-rfc-791 | 0 |

**Total**: 164 regex hits across 8 packages. AST-walk fire count expected lower (the 6 forwarders in `swift-binary-primitives` carry `@_disfavoredOverload` and will be exempted; the regex over-counts those).

## Test suite

`swift test --filter Byte`: 51 tests pass. Per-rule sub-suite "binary serializable uint8 witness Tests": 2 Unit + 3 Edge Case + 1 Integration + 1 Performance = 7 tests, all pass.

## Branch decision

Branch 1 (batch-fix). These are real true-positive witnesses from the W2 cascade. Per the principal's W2 PAUSE direction, the rule's surfacing IS the work-prioritization input for the next "mechanical sweep" arc. Per-package fire-count gives the sweep its work queue order (largest packages first: iso-32000, rfc-4648, ascii-primitives, …).

## Outcome record

`swift-institute/Audits/PROMOTE-API-BYTE-003-2026-05-19.md`.
