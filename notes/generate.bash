#!/bin/bash
#
set -eou pipefail

./node_modules/.bin/mmdc -i websocket_sync_states.mmd -o websocket_sync_states.svg

./node_modules/.bin/mmdc -i websocket_sync_initial.mmd -o wss_initial.svg
./node_modules/.bin/mmdc -i websocket_sync_handshake.mmd -o wss_handshake.svg
./node_modules/.bin/mmdc -i websocket_sync_peered_waiting.mmd -o wss_peered_waiting.svg
./node_modules/.bin/mmdc -i websocket_sync_peered_syncing.mmd -o wss_peered_syncing.svg
./node_modules/.bin/mmdc -i websocket_sync_closed.mmd -o wss_closed.svg

