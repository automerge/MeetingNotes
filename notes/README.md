# Technical Notes

## Generating SVG from Mermaid Diagrams

To manually generate SVG files from the existing mermaid diagrams:

    npm i @mermaid-js/mermaid-cli
    ./node_modules/.bin/mmdc -i websocket_sync_states.mmd -o websocket_sync_states.svg
