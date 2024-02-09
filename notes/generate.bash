#!/bin/bash
#
set -eou pipefail

./node_modules/.bin/mmdc -i websocket_sync_states.mmd -o websocket_sync_states.svg

./node_modules/.bin/mmdc -i websocket_sync_initial.mmd -o wss_initial.svg
./node_modules/.bin/mmdc -i websocket_sync_handshake.mmd -o wss_handshake.svg
./node_modules/.bin/mmdc -i websocket_sync_peered.mmd -o wss_peered.svg
./node_modules/.bin/mmdc -i websocket_sync_closed.mmd -o wss_closed.svg

./node_modules/.bin/mmdc -i websocket_strategy_sync.mmd -o websocket_strategy_sync.svg
./node_modules/.bin/mmdc -i websocket_strategy_request.mmd -o websocket_stragegy_request.svg