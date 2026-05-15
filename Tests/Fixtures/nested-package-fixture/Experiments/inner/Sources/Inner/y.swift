// Fixture file inside a nested experiment package — MUST NOT appear in
// the outer walker's emitted paths. Carries a call-site `__unchecked:`
// violation; if the walker incorrectly descends into the nested package,
// a fixture-rule will fire here and the count assertion will trip.

let _ = OtherType(__unchecked: ())
