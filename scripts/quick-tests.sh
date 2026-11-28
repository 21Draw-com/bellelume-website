#!/bin/bash
# This repository's quick lane (kit 1.4.0, run by scripts/preflight.sh): the tier=quick tests of .github/test-register.txt.
# Not a kit file. Today the register has one quick folder, tests/ (the kit's shell test of scripts/job-session.sh).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
for t in "$root"/tests/*.test.sh; do
  [ -e "$t" ] || continue
  echo "-- $(basename "$t")"
  bash "$t" || fail=1
done
exit "$fail"
