#!/usr/bin/env bash
set -eou pipefail

# see https://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
THIS_SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
PACKAGE_PATH=$THIS_SCRIPT_DIR/../

export DEVELOPER_DIR=/Applications/Xcode.app
pushd ${PACKAGE_PATH}
xcodebuild clean build -scheme 'MeetingNotes' -destination 'platform=iOS Simulator,OS=16.4,name=iPhone 8' -sdk iphonesimulator16.4
xcodebuild clean build -scheme 'MeetingNotes' -destination 'platform=macOS' -sdk macosx13.3
