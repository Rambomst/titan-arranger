#!/usr/bin/env bash
# Gets forever_sim, the headless Forever client the scenario tests run on, with the Blizzard UI source and client
# tables it runs against, then prints the environment tests/run.sh runs it with:
#
#   FOREVER_SIM=<the forever_sim folder>/
#   TITANARRANGER_SIM_CACHE=<the sim's own cache>
#
# forever_sim comes from cjber/forever-core at the commit in tests/forever_sim.txt, fetched once and only that
# folder. FOREVER_SIM names another forever_sim folder instead, such as a forever-core checkout's. The sim's fetch.py
# then adds what its pinned build needs and the cache lacks. TITANARRANGER_CACHE moves the cache from
# ~/.cache/titanarranger-sim.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache="${TITANARRANGER_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/titanarranger-sim}"
# Where forever-core keeps forever_sim, as the sync.py of the copies vendored into addon repos names it.
producer=.agents/skills/wow-forever-addon/tooling/forever_sim

if [[ -n "${FOREVER_SIM:-}" ]]; then
	if ! sim=$(cd "$FOREVER_SIM" 2>/dev/null && pwd); then
		echo "FOREVER_SIM is not a folder: $FOREVER_SIM" >&2
		exit 2
	fi
else
	rev=$(grep -vE '^[[:space:]]*(#|$)' "$here/forever_sim.txt" | head -1)
	if [[ ! "$rev" =~ ^[0-9a-f]{40}$ ]]; then
		echo "tests/forever_sim.txt should name a full forever-core commit, not '$rev'" >&2
		exit 2
	fi
	checkout="$cache/forever-core/$rev"
	if [[ ! -f "$checkout/.complete" ]]; then
		rm -rf "$checkout"
		mkdir -p "$checkout"
		git init -q "$checkout"
		# The commit's trees, then only forever_sim's files: a partial, sparse checkout of under a megabyte.
		git -C "$checkout" remote add origin https://github.com/cjber/forever-core
		git -C "$checkout" config remote.origin.promisor true
		git -C "$checkout" config remote.origin.partialclonefilter blob:none
		git -C "$checkout" sparse-checkout set --no-cone "/$producer/"
		git -C "$checkout" fetch -q --depth 1 --filter=blob:none origin "$rev"
		git -C "$checkout" checkout -q FETCH_HEAD
		touch "$checkout/.complete"
	fi
	sim="$checkout/$producer"
fi
if [[ ! -f "$sim/sim.lua" || ! -f "$sim/fetch.py" ]]; then
	echo "no forever_sim in $sim" >&2
	exit 2
fi

# Standard output carries the environment, so fetch.py's report goes to standard error.
python3 "$sim/fetch.py" --cache "$cache/sim" >&2
printf 'FOREVER_SIM=%s/\nTITANARRANGER_SIM_CACHE=%s\n' "$sim" "$cache/sim"
