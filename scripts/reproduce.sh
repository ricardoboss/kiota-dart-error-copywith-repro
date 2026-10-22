#!/usr/bin/env bash
# Usage: scripts/reproduce.sh <kiota-version> [pinned|latest]   (e.g. 1.36.1 pinned)
# Env:   DART (default: dart). Needs the dotnet SDK and dart on PATH.
# "latest" rewrites the runtime pins in pubspec.yaml to `any` (working copy only; restores it afterwards).
# Exit 0  = generated code compiles and the adapter output equals expected/observed.txt (subtype erased).
# Exit 1  = adapter output differs from expected (behaviour changed, e.g. fixed upstream).
# Exit 2  = setup failure (install/generate/pub get/analyze/run crash).
set -uo pipefail
cd "$(dirname "$0")/.."
ver="${1:?kiota version}"
mode="${2:-pinned}"
DART="${DART:-dart}"
tools=".tools/kiota-$ver"
out="out/$ver-$mode"
mkdir -p "$out"
setup_fail() { echo "SETUP FAILURE: $*" >&2; exit 2; }

if [ "$mode" = latest ]; then
  cp pubspec.yaml "$out/pubspec.yaml.orig"
  trap 'cp "$out/pubspec.yaml.orig" pubspec.yaml' EXIT
  sed -i -E 's/^(  microsoft_kiota_[a-z_]+): [0-9.]+$/\1: any/' pubspec.yaml
fi

if [ ! -x "$tools/kiota" ]; then
  dotnet tool install Microsoft.OpenApi.Kiota --version "$ver" --tool-path "$tools" >"$out/install.log" 2>&1 \
    || { cat "$out/install.log" >&2; setup_fail "kiota $ver install"; }
fi
"$tools/kiota" --version | tee "$out/kiota-version.txt"
grep -q "^$ver" "$out/kiota-version.txt" || setup_fail "kiota version mismatch"

rm -rf lib pubspec.lock
"$tools/kiota" generate --language Dart --openapi openapi.yaml \
  --class-name ReproClient --namespace-name repro --output lib/src --clean-output \
  --exclude-backward-compatible >"$out/generate.log" 2>&1 \
  || { cat "$out/generate.log" >&2; setup_fail "kiota generate"; }
[ -f lib/src/models/conflict_problem_dto.dart ] || setup_fail "generated model missing"

"$DART" pub get >"$out/pub-get.log" 2>&1 || { cat "$out/pub-get.log" >&2; setup_fail "pub get"; }
awk '/^  microsoft_kiota_/{n=$1} /^    version:/{if(n){print n, $2; n=""}}' pubspec.lock | tee "$out/runtime-versions.txt"

# The generated client itself must compile cleanly (this repro is not about compile errors).
"$DART" analyze lib bin >"$out/analyze.log" 2>&1 || { cat "$out/analyze.log" >&2; setup_fail "analyzer errors"; }
"$DART" run bin/observe.dart >"$out/observed.txt" 2>"$out/observe.err" \
  || { cat "$out/observe.err" >&2; setup_fail "bin/observe.dart crashed"; }
cat "$out/observed.txt"

diff -u expected/observed.txt "$out/observed.txt" \
  || { echo "UNEXPECTED adapter output (diff above)" >&2; exit 1; }
echo "OK: adapter output matches expected/observed.txt"
