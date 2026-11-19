#!/usr/bin/env bash
# Prints the folder holding Titan Panel's own addon folders (Titan, TitanBag, TitanXP...) that the scenario tests
# load. TITAN_DIR names one already unpacked, such as a game's AddOns folder. Otherwise the release pinned in
# tests/titan.txt is fetched once from CurseForge's file server and unpacked into the cache
# (TITANARRANGER_CACHE, default ~/.cache/titanarranger-sim) as titan/<version>. Titan is All Rights Reserved, so it
# is fetched at test time and never committed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache="${TITANARRANGER_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/titanarranger-sim}"

if [[ -n "${TITAN_DIR:-}" ]]; then
	if ! dir=$(cd "$TITAN_DIR" 2>/dev/null && pwd); then
		echo "TITAN_DIR is not a folder: $TITAN_DIR" >&2
		exit 2
	fi
else
	read -r version file_id file_name < <(grep -vE '^[[:space:]]*(#|$)' "$here/titan.txt" | head -1)
	if [[ ! "$file_id" =~ ^[0-9]{5,}$ ]]; then
		echo "tests/titan.txt should name a version, a CurseForge file id and a file name" >&2
		exit 2
	fi
	dir="$cache/titan/$version"
	if [[ ! -f "$dir/Titan/Titan.toc" ]]; then
		tmp=$(mktemp -d)
		trap 'rm -rf "$tmp"' EXIT
		# CurseForge's file server path: the id's first four digits, then the rest without leading zeros.
		url="https://mediafilez.forgecdn.net/files/${file_id:0:4}/$((10#${file_id:4}))/$file_name"
		echo "fetching $url" >&2
		curl -fsSL "$url" -o "$tmp/titan.zip"
		rm -rf "$dir"
		mkdir -p "$dir"
		unzip -q "$tmp/titan.zip" -d "$dir"
	fi
	if ! grep -q "^## Version: $version" "$dir/Titan/Titan.toc"; then
		echo "$dir does not hold Titan $version" >&2
		exit 2
	fi
fi
if [[ ! -f "$dir/Titan/Titan.toc" ]]; then
	echo "no Titan in $dir" >&2
	exit 2
fi
printf '%s\n' "$dir"
