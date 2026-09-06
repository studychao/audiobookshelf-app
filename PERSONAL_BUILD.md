# Personal iOS build

This fork retains the upstream Audiobookshelf client and GPL-3.0 license. Bundle ID: `com.chaowu.audiobookshelf`. Personal build: **0.14.1 (45)**. Host minimum iOS 15; App Shortcuts need iOS 16; the widget needs iOS 17.

## Features

The core app adds an import/organization page, a continue-listening home section, readable player controls and sync status, persistent download recovery, response/file-size validation, bounded retries, and acknowledged progress syncing with stale-session conflict protection. Native Files “Open in” and file selection work in the core build for audio and EPUB/PDF/MOBI/AZW3/CBZ/CBR ebooks. Ebook-only imports and combined audio/ebook books are supported; choose the default reading version when importing several versions. The import companion must be deployed at the selected server's `/personal/` route.

The full build also embeds:

- `AudiobookshelfShare`: receive audio/cover files from the iOS share sheet; open the app's 添加 page to confirm metadata and upload.
- `AudiobookshelfWidget`: continue-listening widget for small/medium home-screen sizes.
- Two App Shortcuts in the host: 继续听书 and 添加有声书.

The App Group `group.com.chaowu.audiobookshelf` shares imported files and non-sensitive playback display state. Server credentials stay in the host app's existing storage. Uploaded inbox files are removed only after a confirmed successful import.

## Build and sign

Use Xcode with an Apple developer account that has permission for Team `3F6GUF4Q64`. Automatic signing must be able to register the host, `.share` and `.widget` bundle IDs and the App Group.

```sh
npm ci
ABS_DEFAULT_SERVER_URL=https://books.example.com npm run generate
npx cap sync ios
ruby ios/configure-personal.rb
xcodebuild -workspace ios/App/App.xcworkspace -scheme App \
  -configuration Debug -destination 'id=YOUR_DEVICE_UDID' \
  -derivedDataPath ../build-ios -allowProvisioningUpdates build
```

The server URL is an optional non-secret default, only prefilled when no connection is saved. Never put passwords or server tokens into build configuration.

`configure-personal.rb` requires the `xcodeproj` gem. On this Mac it is bundled with CocoaPods:

```sh
GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.17.0/libexec \
  /opt/homebrew/opt/ruby/bin/ruby ios/configure-personal.rb
```

If only the existing wildcard profile is available, `ruby ios/configure-personal.rb --core` removes extension embedding and App Group signing from the host. That build uses its private app container for imported files and playback display state, and can be signed with the existing profile. It does not include the share extension or widget. Run the generator without flags to restore the full project before committing. Switching from core to full starts a new shared inbox/display state; the existing ABS login, downloaded books and progress remain in the main database.

Install `Audiobookshelf.app` using Xcode or:

```sh
xcrun devicectl device install app --device YOUR_DEVICE_ID /absolute/path/Audiobookshelf.app
xcrun devicectl device process launch --device YOUR_DEVICE_ID com.chaowu.audiobookshelf
```

## CarPlay

The optional implementation provides the last book, downloaded books, native playback controls and the Now Playing screen. It can start the existing audio engine without the phone WebView being loaded. It does not add credentials to extensions.

CarPlay is disabled in the default project. Apple must grant `com.apple.developer.carplay-audio` for the app before a device profile can include it. After that grant:

```sh
ruby ios/configure-personal.rb --carplay
```

This switches the host to `Personal/CarPlay.entitlements` and registers phone/CarPlay scene delegates. Extensions continue using only the App Group entitlement. Rebuild with the granted profile and validate on a CarPlay simulator/head unit before using it in a vehicle. Run without flags to disable CarPlay again. The CarPlay code is compiled in normal builds, but the default build does not advertise an ungranted capability.

Apple guidance: https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements

## Tests

```sh
xcodebuild -workspace ios/App/App.xcworkspace -scheme App \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -parallel-testing-enabled NO -derivedDataPath ../build-ios-simulator \
  CODE_SIGNING_ALLOWED=NO test
```

Tests cover HTTP authentication failures, truncated/empty files, bounded retries, attempted versus acknowledged sync timing, preservation of in-flight listening time, stale remote progress, session cleanup races and existing seek-back behavior. A full simulator build validates the extension targets. Device signing, share-sheet behavior, widget refresh and CarPlay activation require their respective real profiles and device checks; compiling code alone does not verify those user flows.
