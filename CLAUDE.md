# SnoozeFest

SwiftUI + SwiftData + Swift Charts iPhone app (iOS 18+) for tracking a child's sleep and interventions.

## Layout
- `SnoozeFest/Models`
  - `SleepEntry` and `Intervention` (SwiftData models)
  - plain value snapshots `Night` and `InterventionEvent`
  - `Day` date helpers
- `SnoozeFest/Analysis`
  - `Stats`: Welch t-test, Fisher exact, t distribution, moving average
  - `EffectAnalysis`: before/after windows per `InterventionGroup`
- `SnoozeFest/Data`
  - `CSVCodec` for the import/export format
  - `DataStore` for replace-all and delete-all
- `SnoozeFest/Views`: a single screen, `HomeView` (chart panel from `TrendsPanel` on top, logs below), plus Settings (sheet), the editors and `ChangeViews` (per-intervention result rows and cards).
- `SnoozeFestTests`: Swift Testing. Statistics reference values come from scipy.

## Conventions
- All dates are the local start of day of the **wake-up morning**. An intervention's date is the first morning it affects, and it's drawn between that night and the previous one.
- Analysis and CSV code work on the value types (`Night`, `InterventionEvent`), never on SwiftData models, so they stay unit-testable.
- The project uses synchronized folders. Add files to the folders; don't edit `project.pbxproj` to add sources.
- No hard-coded or sample data in the app. Personal data lives only in the gitignored `private/` folder.

## Test
`xcodebuild test -project SnoozeFest.xcodeproj -scheme SnoozeFest -destination 'platform=iOS Simulator,name=iPhone 17'`
