#!/usr/bin/env bash
set -eou pipefail

# see https://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
THIS_SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
REPO_DIR=$THIS_SCRIPT_DIR/../

cd ${REPO_DIR}
if [ ! -d automerge-repo-sync-server ]; then
    git clone https://github.com/automerge/automerge-repo-sync-server.git
fi

cd automerge-repo-sync-server
git fetch --all --prune
git reset --hard origin/main
npm i
npm start