// swift-tools-version: 6.0
// Fixture consumer manifest. The walker treats this manifest's directory
// as the run-root; this file IS included in the emitted source paths
// because its parent equals the root (`parent != root` filters it out
// of `nestedPackageRoots`, leaving the file itself eligible for linting).
import PackageDescription

let package = Package(name: "nested-package-fixture")
