#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src="$root_dir/web/dist"
dest="$root_dir/macos/Pasteur/Resources/web-dist"

mkdir -p "$dest"
rsync -a --delete "$src/" "$dest/"
