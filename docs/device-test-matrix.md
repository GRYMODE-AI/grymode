# Device test matrix

Grymode is one universal app. Each phase is verified on the configurations below before it is called complete.

## Layout configurations

| Configuration | Width class | Navigation | What to check |
|---|---|---|---|
| Small iPhone portrait (iPhone SE / 17e) | compact | Tab bar | No clipping, bottom actions above home indicator |
| Large iPhone portrait (Pro Max) | compact | Tab bar | Comfortable margins, no stretched cards |
| Large iPhone landscape | regular height-compact | Tab bar or sidebar per size class | Content scrolls, bottom bar readable |
| iPad portrait | regular | Sidebar | Readable width cap, sidebar selection |
| iPad landscape | expanded | Sidebar | Side-by-side cards, grid columns increase |
| iPad Split View ⅓ / Slide Over | compact | Tab bar | Shell switches without losing the selected section |
| iPad Split View ½ | regular or compact | Either | State preserved across resizing |
| Accessibility XXXL text (iPhone and iPad) | any | any | Everything reachable by scrolling; chips wrap; no truncated actions |
| VoiceOver | any | any | Labels, selected traits on chips, logical order |

## Simulator commands

```sh
xcrun simctl list devices available

# Larger text on a booted simulator
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
xcrun simctl ui booted content_size large   # reset

# Screenshot
xcrun simctl io booted screenshot ~/Desktop/grymode.png
```

Split View and Slide Over are checked manually on an iPad simulator.

## Automated screenshot capture

`LayoutScreenshotTests` walks every Phase 1 screen and attaches a screenshot of each. It's skipped unless
requested:

```sh
cd ios
TEST_RUNNER_GRYMODE_SCREENSHOTS=1 TEST_RUNNER_GRYMODE_ORIENTATION=landscape \
  xcodebuild test -project Grymode.xcodeproj -scheme Grymode \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -only-testing:GrymodeUITests/LayoutScreenshotTests -resultBundlePath ../build/shots.xcresult
xcrun xcresulttool export attachments --path ../build/shots.xcresult --output-path ../artifacts/screenshots
```

Set the text size on the simulator first (see above) to capture accessibility sizes. Landscape captures are
saved rotated; the layout itself is in landscape. Screenshots go to `artifacts/`, which git ignores.

## Phase 1 results (iOS 27 simulators, 2026-10-10)

| Configuration | Automated suites | Screenshot review |
|---|---|---|
| iPhone 17e | 60 passed, 0 failed (1 skipped: screenshot capture) | — |
| iPad Pro 13-inch (M5) | 60 passed, 0 failed (1 skipped: screenshot capture) | Portrait and landscape: sidebar, capped content width, side-by-side Home cards |
| iPhone SE (3rd generation) | — | All 10 screens; paired choices stack when they don't fit |
| iPhone 18 Pro Max | — | All 10 screens |
| iPhone SE, accessibility XXXL | — | All 10 screens scroll; no clipped actions |
| iPad mini (A17 Pro), accessibility XXXL | — | Home screen captured with `simctl` (tab bar, stacked cards). The XCUITest capture crashed while the test runner was starting up, from host memory pressure |

Defects found and fixed during the review:

- Paired choice chips broke words mid-word on small phones. Fixed with `EqualWidthRow` and a stable chip width.
- Multi-select chips wrapped or truncated on iPad. Fixed with a compact checkmark inset and a 160 pt minimum width.
- The sidebar broke section names mid-word at accessibility sizes. iPad now uses the tab bar at those sizes.
- The Home cards stayed side by side at accessibility sizes. They now stack.

## Phase 2 results (accounts + API, 2026-10-10)

Verified on the local stack (`./scripts/dev-stack.sh`: Supabase Auth, Postgres RLS, Mailpit, Grymode API).

| Suite | Result |
|---|---|
| Backend unit + integration (pytest) | 71 passed |
| Database RLS (pgTAP) | 17/17 passed |
| Backend ruff, mypy strict, pip-audit | clean |
| Docker image smoke (`/v1/health`, 401 contract, non-root) | passed |
| iOS unit tests (iPhone 17e) | 103 passed, 0 failed, 0 warnings |
| iOS swift-format lint | clean |
| iOS E2E UI (`GrymodeUITests`, stack required, iPhone 17e) | 5/5 passed (run one-at-a-time) |

E2E journeys covered in `GrymodeUITests`: skip then sign in → all sections; preferences sync and survive
relaunch; sign out and sign back in restores style; delete account returns to Welcome with subscription
notice; Looks empty state → Wardrobe.

Host note: this Mac (8 GB) often runs out of free memory while Docker and the simulator share the machine.
Full-suite UI runs can crash the XCTest runner during accessibility bootstrap (`XCTWaiter` stall / Mach
error -308). Running the five E2E cases one at a time after a cold `simctl boot` is the reliable path.
iPad Pro 13-inch (M5) E2E was not re-run under that pressure; unit coverage and Phase 1 layout review still
apply.

Defects found and fixed during Phase 2 verification:

- Supabase's per-address OTP throttle (`over_email_send_rate_limit` with “after N seconds”) was treated as a
  hard failure. The app now continues to the verify screen and offers resend when the earlier code was already used.
- Signing out from Profile left that tab selected; signing back in opened Profile instead of Home. The router
  now resets to Home when returning to onboarding.
- Nested `@Observable` updates did not always refresh the root phase; `AppModel` now stores `phase` and
  refreshes it from an account presentation callback.
- Mailpit reachability checks in UI tests could time out on a loaded host; they retry briefly before skipping.

Not yet covered: VoiceOver walkthrough, Split View and Slide Over resizing (manual), physical devices,
Sign in with Apple (needs Apple Developer Team ID), hosted Supabase / Cloud Run.
