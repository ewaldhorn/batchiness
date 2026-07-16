#!/usr/bin/env bash
# Builds the Batchiness docs example to WASM.
#
# Build flags: -target:js_wasm32 (WASM target), -o:size (size optimization),
# -no-entry-point (library mode — driven by JS-called exports, not main()).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

FLAGS=(-target:js_wasm32 -o:size -no-entry-point)

echo "==> building docs example"
odin build docs -out:docs/example.wasm "${FLAGS[@]}"

# docs/ must be self-contained for GitHub Pages, which serves only that directory. Copy the JS
# glue in so index.html can load it via a relative "./batchiness.js".
cp web/batchiness.js docs/batchiness.js

echo
echo "Done. Serve the repo root with any static file server and open:"
echo "  docs/index.html"
