#!/usr/bin/env bash
# Take the CSV produced by export-windows-programs.ps1 and tell you, for each
# Windows program, whether something with that name exists in nixpkgs.
#
#   ./match-nixpkgs.sh installed-programs.csv > matches.md
#
# This is a first pass, not an answer. Names differ across ecosystems
# ("Notepad++" vs "notepad-plus-plus"), and a name match doesn't mean it's the
# same project. Treat hits as candidates to eyeball.

set -euo pipefail

CSV="${1:?usage: match-nixpkgs.sh installed-programs.csv}"
[ -f "$CSV" ] || { echo "no such file: $CSV" >&2; exit 1; }

command -v nix >/dev/null || { echo "needs nix in PATH" >&2; exit 1; }

echo "# Windows programs vs nixpkgs"
echo
echo "| Windows | nixpkgs candidate | note |"
echo "|---|---|---|"

# Skip the header row, take column 1, strip quotes.
tail -n +2 "$CSV" | cut -d, -f1 | tr -d '"' | while IFS= read -r name; do
  [ -z "$name" ] && continue

  # Normalise: lowercase, drop version numbers and common vendor noise, then
  # collapse anything non-alphanumeric to a single space.
  query=$(printf '%s' "$name" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/\(64-bit\)|\(32-bit\)|\(x64\)|\(x86\)//g' \
    | sed -E 's/[0-9]+(\.[0-9]+)*//g' \
    | sed -E 's/(microsoft|corporation|inc|llc|ltd)//g' \
    | sed -E 's/[^a-z0-9]+/ /g' \
    | sed -E 's/^ +| +$//g')

  [ -z "$query" ] && continue

  # First word is usually the product name; search on that to avoid
  # over-constraining.
  head=$(printf '%s' "$query" | cut -d' ' -f1)
  [ ${#head} -lt 3 ] && continue

  hit=$(nix search nixpkgs "^${head}$" --json 2>/dev/null \
        | jq -r 'keys[]' 2>/dev/null \
        | head -1 \
        | sed 's/^legacyPackages\.[^.]*\.//' || true)

  if [ -n "$hit" ]; then
    echo "| $name | \`$hit\` | exact-ish |"
  else
    hit=$(nix search nixpkgs "$head" --json 2>/dev/null \
          | jq -r 'keys[]' 2>/dev/null \
          | head -3 \
          | sed 's/^legacyPackages\.[^.]*\.//' \
          | paste -sd', ' || true)
    if [ -n "$hit" ]; then
      echo "| $name | $hit | fuzzy — check |"
    else
      echo "| $name | — | no match |"
    fi
  fi
done
