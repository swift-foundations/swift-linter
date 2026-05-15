// swift-tools-version: 6.0
// Nested experiment package manifest. The walker MUST treat this
// manifest's parent directory (`Experiments/inner/`) as the root of an
// independent SwiftPM package whose subtree is skipped during the
// outer consumer's lint run.
import PackageDescription

let package = Package(name: "inner")
