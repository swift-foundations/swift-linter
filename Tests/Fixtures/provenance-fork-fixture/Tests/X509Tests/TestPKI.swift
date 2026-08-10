// ===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftCertificates open source project
//
// Copyright (c) 2022 Apple Inc. and the SwiftCertificates project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//
// Fixture: an Institute-authored addition INSIDE the fork that copies the
// upstream header style but is NOT enumerated in the central vendored scope.
// NEAR-MISS: must still be linted — the boundary between vendored and
// Institute-authored files is the central enumeration, not the header.

let _ = SomeType(__unchecked: ())
