#!/usr/bin/env bash
set -eou pipefail

# see https://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
THIS_SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
PACKAGE_PATH=$THIS_SCRIPT_DIR/../

export DOCC_JSON_PRETTYPRINT=YES
export DOCC_HOSTING_BASE_PATH=MeetingNotes
export DOCUMENTATION_FOLDER_PATH=${PACKAGE_PATH}/docs
export OTHER_DOCC_FLAGS="--source-service github --source-service-base-url https://github.com/automerge/meetingnotes/tree/main --checkout-path ${PACKAGE_PATH}"

rm -rf ~/MeetingNotesBuild
mkdir -p ${PACKAGE_PATH}/docs

pushd ${PACKAGE_PATH}
# xcodebuild -list -project MeetingNotes.xcodeproj // -json
# xcodebuild -showsdks
xcodebuild docbuild -scheme MeetingNotes \
-derivedDataPath ~/MeetingNotesBuild
# DOCC_HOSTING_BASE_PATH=MeetingNotes \
# DOCUMENTATION_FOLDER_PATH=${PACKAGE_PATH}/docs \
# OTHER_DOCC_FLAGS="--source-service github --source-service-base-url https://github.com/automerge/meetingnotes/tree/main --checkout-path ${PACKAGE_PATH}"

# find ~/Desktop/MeetingNotesBuild -type d -name '*.doccarchive`
# /Users/heckj/Desktop/MeetingNotesBuild/Build/Products/Debug/MeetingNotes.doccarchive

# mkdir -p ${PACKAGE_PATH}/docs

# $(xcrun --find docc) process-archive transform-for-static-hosting --help

$(xcrun --find docc) process-archive \
transform-for-static-hosting ~/MeetingNotesBuild/Build/Products/Debug/MeetingNotes.doccarchive \
--output-path ${PACKAGE_PATH}/docs \
--hosting-base-path MeetingNotes

# expecting resulting (hosted) docs at
#   https://automerge.org/MeetingNotes/documentation/meetingnotes/
