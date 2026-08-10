// swift-tools-version: 6.3.3
// Provenance fixture: a package that is NOT in the central fork register
// but whose files falsely claim upstream heritage via a copied header.
// This is a test fixture tree, not a real package.
import PackageDescription

let package = Package(
    name: "swift-provenance-nonfork"
)
