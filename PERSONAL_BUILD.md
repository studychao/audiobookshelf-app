# Personal iOS build

This fork retains the upstream Audiobookshelf client and GPL-3.0 license.
The bundle identifier is `com.chaowu.audiobookshelf` and the minimum iOS version is 15.

The server URL is optional build configuration, not an authentication credential:

```sh
npm ci
ABS_DEFAULT_SERVER_URL=https://books.example.com npm run generate
npx cap sync ios
xcodebuild -workspace ios/App/App.xcworkspace -scheme App \
  -configuration Debug -destination 'id=YOUR_DEVICE_UDID' \
  -derivedDataPath ../build-ios -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

The address is prefilled only when there are no saved server connections.
Passwords and server tokens must never be embedded in the app or committed.
The original native audio player, background audio, downloads, and progress sync remain in use.

Install the resulting `Audiobookshelf.app` with Xcode or `xcrun devicectl device install app`.
