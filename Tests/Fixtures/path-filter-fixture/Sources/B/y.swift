// Fixture B — contains a call-site `__unchecked:` violation that
// `Lint.Rule.Unchecked` fires on. Used by Lint.Run tests to exercise
// per-rule path-filter discrimination at the engine layer.

let _ = OtherType(__unchecked: ())
