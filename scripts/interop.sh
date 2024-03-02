#!/usr/bin/env bash
set -eou pipefail

# see https://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
THIS_SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
REPO_DIR=$THIS_SCRIPT_DIR/../

cd ${REPO_DIR}
if [ ! -d automerge-repo-sync-server ]; then
    gh repo clone heckj/automerge-repo-sync-server
fi

cd automerge-repo-sync-server
git fetch --all --prune
git reset --hard origin/sync_debug
yarn install
NODE_ENV=dev DEBUG=* node ./src/index.js

