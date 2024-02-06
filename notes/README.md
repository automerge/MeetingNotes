# Technical Notes

## Generating SVG from Mermaid Diagrams

To manually generate SVG files from the existing mermaid diagrams:

    npm i @mermaid-js/mermaid-cli
    ./node_modules/.bin/mmdc -i websocket_sync_states.mmd -o websocket_sync_states.svg

Generate the compact left-to-right views with a single state highlighted, for annotating other bits of documentation:

    npm i @mermaid-js/mermaid-cli
    ./node_modules/.bin/mmdc -i websocket_sync_initial.mmd -o wss_initial.svg
    ./node_modules/.bin/mmdc -i websocket_sync_handshake.mmd -o wss_handshake.svg
    ./node_modules/.bin/mmdc -i websocket_sync_peered_waiting.mmd -o wss_peered_waiting.svg
    ./node_modules/.bin/mmdc -i websocket_sync_peered_syncing.mmd -o wss_peered_syncing.svg
    ./node_modules/.bin/mmdc -i websocket_sync_closed.mmd -o wss_closed.svg
