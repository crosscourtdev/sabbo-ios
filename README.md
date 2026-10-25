# Sabbo for iOS and Mac

Sabbo is a native SwiftUI study client: write answers in your own words, save
local drafts, review feedback, and follow shared progress. The interface is in
Norwegian Bokmål. iOS/iPadOS 18 and macOS 15 (Mac Catalyst) are supported.

This repository owns the shared client implementation, tests and Xcode generator.
It contains original sample exercises and simple placeholder artwork. The
production curriculum, personal artwork, account configuration, backend and
signing material are maintained separately and are not included here. This is
client source, not a hosted service or an App Store release.

## Build and explore

Use Xcode 26.3 or newer and Python 3. No third-party Swift packages are required.

```sh
python3 tools/generate_xcode.py
open ios/Sabbo.xcodeproj
```

Select the Sabbo scheme and an iPhone simulator. To explore without a server,
add the environment variable `SABBO_UI_TEST=1` to the Debug scheme's Run action.
Optionally set `SABBO_RESULT_FIXTURE=graded` or `SABBO_BONUS_FIXTURE=waiting`.
These synthetic fixtures are compiled out of Release builds.

The default API is `https://api.example.invalid`, deliberately unreachable.
To use your own compatible backend, edit `config/native.json`, including your
bundle ID, HTTPS API URL and presentation profile, then regenerate the project.
The OAuth callback is `<bundle_id>:/oauth/callback`; the backend must advertise
that exact callback. Client presentation settings confer no server permissions.
Device builds require your own Apple signing configuration. Never commit keys,
provisioning profiles, user data or production configuration.

## Validate

```sh
python3 tools/validate_public.py
python3 tools/generate_xcode.py
git diff --exit-code -- ios
xcodebuild -project ios/Sabbo.xcodeproj -scheme Sabbo -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

CI builds iOS and Mac Catalyst, runs model/editor tests on Mac, and exercises
result/bonus UI flows on both platforms. It uses standard GitHub-hosted runners,
read-only permissions, synthetic data and no deployment or signing credentials.
Public CI success does not establish production-backend or physical-device
acceptance. Distribution-specific resources need separate validation.

## License and contributions

Code, original sample exercises and placeholder artwork in this repository are
MIT licensed; see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Contributions
are welcome under that license. See [CONTRIBUTING.md](CONTRIBUTING.md).

Home counters open streak rewards or star rewards and achievements. Question
illustrations are revealed inside the daily quest. Achievement titles and
Norwegian descriptions come from the authenticated progress response; old cached
progress without achievements remains readable.

Before reading or replacing an existing local state file, the client keeps an
untouched `Recovery/before-achievements-v1-<account>.json` copy. It is never
rotated automatically. Decode failures block normal sync and persistence rather
than replacing the file with empty state. **Mine data → Eksporter lokale utkast**
exports the original copy and current local file without a network request or
credentials (base64 preserves even malformed bytes). The recovery copy does not
prove any particular unsynced answer exists. Explicit account-data deletion also
removes that account's local recovery copy; updating through TestFlight does not.

Drafts save locally on each edit and synchronize with one save at a time per
assignment. Each pending write has a durable identifier and base revision. A
compatible backend must return the original receipt when that identifier is
retried with the same payload, without replaying it over a newer draft. The
client acknowledges the receipt before merging the current server version.
Edits to different questions merge automatically; overlapping changes show a
per-question choice with both answers retained. Submission opens that choice
and then returns to the full answer review. `SABBO_DRAFT_FIXTURE=1` exercises
this flow with synthetic answers in Debug builds.

Missed daily sessions are available in **Sammen → Ta igjen økter**, including sessions with no saved draft. Opening a past session restores its private draft and leaves today’s task in place. Late submissions receive grades and feedback under the existing deadline rules; they do not automatically earn stars or streak credit.
