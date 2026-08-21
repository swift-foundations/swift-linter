import Linter
import Linter_Institute_Rules
import Linter_Primitives_Rules
import Linter_Standards_Rules

Lint.run(bundles: [
    .primitives: Lint.Rule.Bundle.primitives,
    .standards: Lint.Rule.Bundle.standards,
    .institute: Lint.Rule.Bundle.institute,
])
