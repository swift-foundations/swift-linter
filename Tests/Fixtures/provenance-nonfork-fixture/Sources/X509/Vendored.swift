// ===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftCertificates open source project
//
// Copyright (c) 2022 Apple Inc. and the SwiftCertificates project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//
// Fixture: falsely claimed heritage — the path and header mimic a declared
// fork, but this package is not in the central register.
// NEAR-MISS: must still be linted (identity resolution fails).

let _ = SomeType(__unchecked: ())
