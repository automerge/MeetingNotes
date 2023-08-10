#!/usr/bin/env bash
set -eou pipefail

# see https://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
THIS_SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
PACKAGE_PATH=$THIS_SCRIPT_DIR/../

export DOCC_JSON_PRETTYPRINT=YES

rm -rf ~/MeetingNotesBuild
mkdir -p ${PACKAGE_PATH}/docs

pushd ${PACKAGE_PATH}
# xcodebuild -list -project MeetingNotes.xcodeproj // -json
# xcodebuild -showsdks
xcodebuild docbuild -scheme MeetingNotes -derivedDataPath ~/MeetingNotesBuild

# find ~/Desktop/MeetingNotesBuild -type d -name '*.doccarchive`
# /Users/heckj/Desktop/MeetingNotesBuild/Build/Products/Debug/MeetingNotes.doccarchive

mkdir -p ${PACKAGE_PATH}/docs

# $(xcrun --find docc) process-archive transform-for-static-hosting --help

$(xcrun --find docc) process-archive \
transform-for-static-hosting ~/MeetingNotesBuild/Build/Products/Debug/MeetingNotes.doccarchive \
--output-path ${PACKAGE_PATH}/docs \
--hosting-base-path MeetingNotes \
# --source-service github \
# --source-service-base-url https://github.com/automerge/meetingnotes/blob/main \
# --checkout-path ${PACKAGE_PATH}