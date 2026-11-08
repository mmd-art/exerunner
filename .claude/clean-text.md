# ExeRunner text context

## Readers and language

README addresses English-speaking Mac users and developers. The app has Russian source strings and an English translation table. Users know Windows programs, Steam and installation; developers know SwiftUI/AppKit, Wine, graphics translators and build tooling. Preserve each source language.

## Voice

Practical and direct. State the action and its scope. Keep alpha, experimental, hardware-validation and per-application compatibility qualifiers beside their claims. Do not turn source availability or notarization into an implied endorsement.

## Terms

| Term | Meaning | Known to |
| --- | --- | --- |
| ExeRunner | Product name | All readers |
| bottle / environment | Windows environment used by Wine | Users and developers |
| engine | Selected Wine runtime | Users and developers |
| Game Boost | Existing macOS Game Mode feature | Users |
| D3DMetal / DXMT / DXVK / MoltenVK / vkd3d | Existing graphics components with distinct compatibility | Developers and advanced users |
| library entry | Launcher record, distinct from its files | Users |

## Text surfaces

- `README.md`
- `app/Sources/ExeRunner/Core/English.swift`

## Protected meaning

Keep release versions, macOS/architecture requirements, code-signing/notarization/compatibility boundaries, GPL and upstream notices, commands, recipe fields, localization keys and formatting placeholders unchanged. Russian keys are code identifiers and remain intact; edit English values only when needed. Remote main c675083 is newer than the original local main and contains the existing artifact policy. Work from that verified remote revision; do not include or overwrite the old local uncommitted changes. No app/engine build, packaging, install, game launch, updater or owner settings action.
