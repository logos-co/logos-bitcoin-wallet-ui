#!/usr/bin/env bash
# Runs the doc-tests: every spec, or the ones named in SPECS. OUT moves the output; the e2e's is large.
set -euo pipefail
cd "$(dirname "$0")"
read -r -a DOCTEST <<< "${DOCTEST:-nix run github:logos-co/logos-doctest --}"
OUT="${OUT:-outputs}"
MARK=.bitcoin-wallet-ui-doctests
if [ -n "$(ls -A "$OUT" 2>/dev/null)" ] && [ ! -e "$OUT/$MARK" ]; then
  echo "OUT=$OUT holds files from something else; not clearing it" >&2; exit 1
fi
chmod -R u+w "$OUT" 2>/dev/null || true
rm -rf "$OUT" && mkdir -p "$OUT" && touch "$OUT/$MARK"
OUT="$(cd "$OUT" && pwd)"
export E2E_REPO="$(cd .. && pwd)"
# A failed e2e step leaves Basecamp and the chain running: stop them by PID.
trap 'E2E_WORK="$OUT" python3 e2e/drive.py cleanup > /dev/null 2>&1 || true' EXIT
for spec in ${SPECS:-*.test.yaml}; do
  [ -f "$spec" ] || spec="$spec.test.yaml"
  echo "==> Running ${spec}"
  "${DOCTEST[@]}" run "$spec" --output-dir "$OUT" --report "$OUT/${spec%.test.yaml}.report.html" "$@"
done
