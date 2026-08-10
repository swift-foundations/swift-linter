// swift-tools-version: 6.3.3
// Provenance fixture: declares the SwiftPM package name of the centrally
// registered fork (swift-foundations/swift-linter#45) so engine tests can
// exercise the exemption predicate against the REAL central register entry.
// This is a test fixture tree, not a real package.
import PackageDescription

let package = Package(
    name: "swift-certificate-verification"
)
