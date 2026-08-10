// Fixture: inside the declared vendored directory but WITHOUT the upstream
// attribution marker — a vendored slot rewritten as Institute code.
// NEAR-MISS: must still be linted (attribution corroboration fails).

let _ = SomeType(__unchecked: ())
