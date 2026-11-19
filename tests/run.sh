#!/usr/bin/env bash
# Runs Titan Panel [Arranger]'s tests: the unit tests of Model.lua, then the scenario tests on forever_sim, the
# headless Forever client from cjber/forever-core, with the real Titan Panel loaded.
#
#   tests/run.sh               # everything
#   tests/run.sh "centre"      # the unit tests, then the scenarios whose name contains the text
#
# Needs luajit, python3, git, curl and unzip. tests/sim.sh fetches the sim at the commit pinned in
# tests/forever_sim.txt, and tests/titan.sh the Titan release pinned in tests/titan.txt, into
# ~/.cache/titanarranger-sim (TITANARRANGER_CACHE moves it). FOREVER_SIM runs the scenarios on another forever_sim
# folder, TITAN_DIR on another unpacked Titan, TITANARRANGER_ADDON_DIR against another copy of the addon.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

luajit "$here/model_test.lua"

sim_env=$("$here/sim.sh")
while IFS='=' read -r name value; do
	export "$name=$value"
done <<<"$sim_env"
TITAN_DIR=$("$here/titan.sh")
export TITAN_DIR

cd "$here"
exec luajit arranger_test.lua "$@"
