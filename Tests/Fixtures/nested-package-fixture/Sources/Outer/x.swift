// Fixture file in the outer consumer's Sources/ — MUST appear in the
// walker's emitted paths. Carries a call-site `__unchecked:` violation
// so a fixture-rule test can also count this file by firing count.

let _ = SomeType(__unchecked: ())
