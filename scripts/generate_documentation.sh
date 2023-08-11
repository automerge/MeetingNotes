#!/usr/bin/env bash
set -eou pipefail

# see https://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
THIS_SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
PACKAGE_PATH=$THIS_SCRIPT_DIR/../

export DOCC_JSON_PRETTYPRINT=YES
export DOCC_HOSTING_BASE_PATH=MeetingNotes
# export DOCUMENTATION_FOLDER_PATH=${PACKAGE_PATH}/docs # doesn't appear to be having a notable effect through Xcodebuild (Xcode 15b5)

# export OTHER_DOCC_FLAGS="--source-service github --source-service-base-url https://github.com/automerge/meetingnotes/tree/main --checkout-path ${PACKAGE_PATH}"
# ^^^ also not taking effect in `xcodebuild docbuild`, may be invoking this parameter incorrectly...

rm -rf ~/MeetingNotesBuild
rm -rf ${PACKAGE_PATH}/docs
mkdir -p ${PACKAGE_PATH}/docs

pushd ${PACKAGE_PATH}
# xcodebuild -list -project MeetingNotes.xcodeproj // -json
# xcodebuild -showsdks
xcodebuild docbuild -scheme MeetingNotes \
-derivedDataPath ~/MeetingNotesBuild \
DOCC_HOSTING_BASE_PATH=MeetingNotes \
OTHER_DOCC_FLAGS="--source-service github --source-service-base-url https://github.com/automerge/meetingnotes/tree/main --checkout-path \$(SOURCE_ROOT)"

# find ~/Desktop/MeetingNotesBuild -type d -name '*.doccarchive`
# /Users/heckj/Desktop/MeetingNotesBuild/Build/Products/Debug/MeetingNotes.doccarchive

mv ~/MeetingNotesBuild/Build/Products/Debug/MeetingNotes.doccarchive/* ${PACKAGE_PATH}/docs/


# expecting resulting (hosted) docs at
#   https://automerge.org/MeetingNotes/documentation/meetingnotes/
