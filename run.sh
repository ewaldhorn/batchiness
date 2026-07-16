#!/usr/bin/env bash
# run.sh — Build the docs example, then start a dev server.
#
# Never open the HTML via file:// — the page fetches its .wasm over HTTP and the browser blocks
# that with a CORS error. Always serve over HTTP.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building WASM ..."
./build.sh

echo "==> Starting dev server on http://localhost:9000 ..."
echo "    docs: http://localhost:9000/docs/index.html"
npx http-server . -p 9000 -c-1
