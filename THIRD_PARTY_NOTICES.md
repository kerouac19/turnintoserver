# Third-party source notices

This development integration retains the upstream turnintoserver code. Its repository
did not supply a reuse license at the baseline commit `21e307a`. These notices do not
license that upstream code or settle permission to distribute the combined application.

## Unplug

`turnintoserver/Display/ExternalDisplayManager.swift` derives from Unplug
`Sources/main.swift`, baseline `88880e2`, copyright 2026 Sezer Iltekin.
Changes adapt display control to instance ownership and the integration safety policy.
The MIT notice is retained in [Licenses/Unplug-MIT.txt](Licenses/Unplug-MIT.txt).

## Vorssaint

`turnintoserver/CleaningMode/CleaningModeManager.swift`, `CleaningUnlockCounter.swift`
and `CleaningMouseReleaseGate.swift` derive from Vorssaint baseline `26d3c9e`,
copyright 2026 Vorssaint, under GPL-3.0-or-later. The manager was modified for this
integration; file headers retain provenance. The license is reproduced in
[Licenses/Vorssaint-GPL-3.0.txt](Licenses/Vorssaint-GPL-3.0.txt).

GPL requirements apply to distribution of a combined derivative application; retaining
these notices alone is not a substitute for those requirements or upstream authorization.
No Vorssaint branding, application assets or complete toolbox is included.
