// Copyright (c) 2022 Apple Inc. and the SwiftCertificates project authors
// Fixture: bare filename with no directory component, carrying the marker.
// POSITIVE CONTROL for the path-scoped exemption class: no directory entry
// may admit it, and no file entry names it — must still be linted.

let _ = SomeType(__unchecked: ())
