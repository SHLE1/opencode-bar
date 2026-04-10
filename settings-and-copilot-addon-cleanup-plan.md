# Settings and Menu Cleanup Plan
## Goal
Simplify the app so it reflects the current product direction:
- The app is multi-provider bar only
- Settings should be the single place for configuration
- The status bar menu should stop showing legacy configuration submenus
- `GitHub Copilot Add-on` must have its own on/off control
- Disabled items must not be displayed and must not be counted
## Confirmed Decisions
1. Remove `Status Bar Options` from the status bar menu
2. Remove `Auto Refresh` from the status bar menu
3. Remove `Menu Bar Display` related UI from Settings
4. Remove `Show Provider Icon` setting from Settings
5. Keep multi-provider bar behavior only
6. Add a dedicated `GitHub Copilot Add-on` toggle
7. When `GitHub Copilot Add-on` is disabled:
   - do not show it in the Pay-as-you-go section
   - do not include it in total cost
   - do not include it in top-spend summary/share text
   - do not show predicted add-on cost
8. Only enabled items should be displayed and counted
## Current State
### Legacy menu configuration still shown
- `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:427-490`
- The status bar menu still builds:
  - `Auto Refresh`
  - `Status Bar Options`
  - `Menu Bar Display`
  - `Enabled Providers`
  - `Critical Badge`
  - `Show Provider Icon`
### Display mode is already effectively fixed to multi-provider
- `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:191-199`
- `menuBarDisplayMode` getter is hardcoded to `.multiProvider`
- This means the display mode picker is already legacy UI
### Settings still expose legacy display controls
- `CopilotMonitor/CopilotMonitor/App/Settings/StatusBarSettingsView.swift:10-33`
- The Settings window still shows:
  - `Menu Bar Display`
  - `Only Show Mode`
  - `Pinned Provider`
### Show Provider Icon is still user-configurable
- `CopilotMonitor/CopilotMonitor/App/Settings/StatusBarSettingsView.swift:55-58`
- `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:253-258`
- This is obsolete for the current single-mode product direction
### Copilot Add-on has no independent toggle
- `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:1654-1716`
- It is currently tied to `isProviderEnabled(.copilot)`
### Copilot Add-on still affects totals and summaries
- Total Pay-as-you-go:
  - `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:888-901`
- Top spend/share line:
  - `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:3379-3400`
- Predicted Add-on display:
  - `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:3947-3956`
## Scope
### In Scope
- Remove legacy config items from the status bar menu
- Simplify the `Status Bar` tab in Settings
- Add a dedicated `GitHub Copilot Add-on` toggle
- Ensure disabled add-on is excluded from display and calculations
- Keep behavior immediate after toggling
### Out of Scope
- Full deletion of all legacy enums and stored preference keys
- Re-architecting status bar rendering
- Refactoring unrelated menu/history code
- Renaming existing provider categories or menu section titles
## Implementation Plan
### 1. Remove legacy configuration from the status bar menu
Update `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`.
Remove menu insertion for:
- `Auto Refresh`
- `Status Bar Options`
Target area:
- `StatusBarController.swift:427-490`
Expected result:
- The status bar menu keeps only actionable runtime items and provider data
- Configuration lives in the Settings window only
Important note:
- Keep internal helper methods only if they are still needed elsewhere
- Prefer not to delete large internal logic in this round unless it is clearly dead and safe to remove
### 2. Simplify the Status Bar tab in Settings
Update `CopilotMonitor/CopilotMonitor/App/Settings/StatusBarSettingsView.swift`.
Remove these controls:
- `Menu Bar Display`
- `Only Show Mode`
- `Pinned Provider`
- `Show Provider Icon`
Keep these controls:
- `Enabled Providers`
- `Multi-Provider Bar Providers`
- `Critical Badge`
Add this control:
- `GitHub Copilot Add-on`
Recommended structure:
- `Enabled Providers`
- `Additional Cost Items`
- `Multi-Provider Bar Providers`
- `Options`
Behavior rules:
- `GitHub Copilot Add-on` is not a provider icon entry
- It must not appear inside `Multi-Provider Bar Providers`
- It is a billing/display toggle only
### 3. Add a dedicated persisted preference for Copilot Add-on
Update `CopilotMonitor/CopilotMonitor/App/Settings/AppPreferences.swift`.
Add a new persisted preference:
- Key: `provider.copilot_add_on.enabled`
- Default: `true`
Add API similar to existing provider toggles:
- `var copilotAddOnEnabled: Bool`
- notification on change, or reuse the existing enabled-items notification path
Recommended behavior:
- Use the same immediate-update pattern as existing settings
- Keep the change surface small and consistent with current `UserDefaults` usage
### 4. Exclude Copilot Add-on from menu display when disabled
Update `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`.
Gate the `Copilot Add-on` pay-as-you-go row with the new preference.
Target area:
- `StatusBarController.swift:1654-1716`
Required behavior:
- If disabled, do not insert:
  - `Copilot Add-on ($X.XX)`
  - `Copilot Add-on (Loading...)`
- Base `GitHub Copilot` quota row remains independent and still follows the normal provider toggle
### 5. Exclude Copilot Add-on from total cost when disabled
Update `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`.
Gate this part of pay-as-you-go total:
- `StatusBarController.swift:891-893`
Required behavior:
- Do not add `copilot.netBilledAmount` into `calculatePayAsYouGoTotal(...)` when the add-on toggle is off
Effect:
- Top-level status bar total updates automatically because:
  - `calculateTotalWithSubscriptions(...)`
  - `formatCostOrStatusBarBrand(...)`
  already depend on the pay-as-you-go total
### 6. Exclude Copilot Add-on from top-spend/share summary when disabled
Update `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`.
Target area:
- `StatusBarController.swift:3390-3394`
Required behavior:
- When disabled, do not append `GitHub Copilot Add-on` to `topPayAsYouGoShareLine()`
### 7. Hide predicted add-on cost when disabled
Update `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`.
Target area:
- `StatusBarController.swift:3947-3956`
Required behavior:
- When disabled, do not render:
  - `Predicted Add-on: $X.XX`
Note:
- This does not require changing the predictor itself in this round
- Only the displayed add-on prediction should be suppressed
- Keep the implementation minimal unless later we want the predictor to become preference-aware too
### 8. Keep multi-provider mode as the only exposed product mode
Apply a minimal cleanup approach.
Recommended approach:
- Remove UI and menu entry points for old modes
- Do not perform a deep removal of legacy enums and code paths in the same round
- Keep compatibility with existing stored data by simply ignoring old mode controls
Reason:
- `StatusBarController` already effectively forces `.multiProvider`
- This avoids risky churn in a large file while delivering the intended product behavior
## Files To Modify
### Primary
- `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`
- `CopilotMonitor/CopilotMonitor/App/Settings/StatusBarSettingsView.swift`
- `CopilotMonitor/CopilotMonitor/App/Settings/AppPreferences.swift`
### Possible Secondary
- `CopilotMonitor/CopilotMonitor/Helpers/MenuEnums.swift`
- Only if a new preference key constant is desired there instead of using a local string key
## Data Model and Preference Plan
### Existing keys to keep using
- `provider.<provider>.enabled`
- `statusBarDisplay.criticalBadge`
- `statusBarDisplay.multiProviderProviders`
### New key to add
- `provider.copilot_add_on.enabled`
### Default behavior
- If the new key does not exist, treat it as `true`
### Migration policy
- No destructive migration
- No need to delete old display-mode keys in this round
- Old keys can remain unused
## Verification Plan
### Build
- Run a full Debug build
- Confirm no Swift compile errors
### Manual behavior checks
1. Open the app and open the status bar menu
2. Confirm `Auto Refresh` is gone from the menu
3. Confirm `Status Bar Options` is gone from the menu
4. Open `Settings...`
5. Confirm the `Status Bar` tab no longer shows:
   - `Menu Bar Display`
   - `Only Show Mode`
   - `Pinned Provider`
   - `Show Provider Icon`
6. Confirm the `Status Bar` tab now shows a dedicated `GitHub Copilot Add-on` toggle
7. Turn `GitHub Copilot Add-on` off
8. Confirm the Pay-as-you-go section no longer shows the add-on row
9. Confirm total cost decreases accordingly
10. Confirm any top-spend/share summary no longer references `GitHub Copilot Add-on`
11. Confirm predicted add-on text is hidden
12. Turn `GitHub Copilot Add-on` back on
13. Confirm the row and counts return immediately
### Regression checks
- `GitHub Copilot` base quota row must still work independently
- Multi-provider icon bar must still show selected providers
- `Critical Badge` must still apply immediately
- `Enabled Providers` toggles must still work as before
- `Auto Refresh Period` in the `General` tab must still update the timer immediately
## Risks
### Low Risk
- Removing Settings UI controls that are already functionally obsolete
- Removing menu items that now duplicate the Settings window
### Medium Risk
- Copilot Add-on currently touches both display and totals
- Missing one call site could create a mismatch where it disappears visually but still affects totals
### Mitigation
- Gate all known call sites in the same change:
  - menu row
  - pay-as-you-go total
  - top-spend/share line
  - predicted add-on text
- Verify off/on behavior in one test pass before considering the task done
## Definition of Done
The task is complete when all of the following are true:
- `Status Bar Options` no longer appears in the status bar menu
- `Auto Refresh` no longer appears in the status bar menu
- The `Status Bar` Settings tab contains only relevant multi-provider settings
- `Show Provider Icon` is no longer user-configurable
- `Menu Bar Display` is no longer user-configurable
- `GitHub Copilot Add-on` has its own toggle in Settings
- Turning off `GitHub Copilot Add-on` removes it from display and all cost counting
- Turning it back on restores both display and counting
- The app builds successfully
- No unrelated provider behavior regresses