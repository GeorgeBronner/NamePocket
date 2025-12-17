fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Generate screenshots for App Store

### ios screenshots_framed

```sh
[bundle exec] fastlane ios screenshots_framed
```

Generate screenshots with device frames

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Setup metadata for App Store

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the app

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Upload to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Upload to App Store

### ios prepare_appstore

```sh
[bundle exec] fastlane ios prepare_appstore
```

Complete App Store preparation: screenshots, metadata, and build

### ios setup_signing

```sh
[bundle exec] fastlane ios setup_signing
```

Setup fastlane match for code signing

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
