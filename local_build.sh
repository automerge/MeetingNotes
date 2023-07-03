#!/usr/bin/env bash

set -e # explicitly fail on error of commands

export DEVELOPER_DIR=/Applications/Xcode.app
xcodebuild clean build -scheme 'MeetingNotes' -destination 'platform=iOS Simulator,OS=16.4,name=iPhone 8' -sdk iphonesimulator16.4
xcodebuild clean build -scheme 'MeetingNotes' -destination 'platform=macOS' -sdk macosx13.3
