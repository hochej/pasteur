#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
web_dir="$root_dir/web"

cd "$web_dir"
bun install
bun run build

"$root_dir/scripts/copy-web-dist.sh"
