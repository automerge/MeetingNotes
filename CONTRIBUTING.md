# Contributing

Issues for this library are tracked on GitHub: [https://github.com/automerge/meetingnotes/issues](https://github.com/automerge/meetingnotes/issues)

## Consistency

Before commiting code, use `swiftformat` with the settings in the repository:

```bash
swiftformat .
``` 

## Building and Developing

The project is set to build for both iOS 14 and macOS 11.
Verify both mac and iOS builds, as [the CI system](.github/workflows/mac_ios.yml) does.

Example command-line builds using Xcode:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app
xcodebuild clean build -scheme 'MeetingNotes' -destination 'platform=iOS Simulator,OS=16.4,name=iPhone 8' -sdk iphonesimulator16.4
xcodebuild clean build -scheme 'MeetingNotes' -destination 'platform=macOS' -sdk macosx13.3
```

If you're building from within Xcode, use the build targets `Any Mac (Apple Silicon, Intel)` and `Any iOS Simulator Device (arm64, x86_64)` to verify the projects builds for all relevant targets.

## Logging

Default logging displays at INFO level and higher by default.

To enable debug logging, run the following command:

    sudo log config --subsystem com.github.automerge.MeetingNotes --mode level:debug
