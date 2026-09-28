#!/usr/bin/env bash
# S1 audio: fetches the CC0 recordings the sound build starts from (tools/audio/build_audio.py) into a cache
# outside the repo. Only public-domain material (CC0 1.0): Kenney's audio packs (a GitHub mirror of kenney.nl,
# each pack ships its License.txt) and OpenGameArt packs filtered by the CC0 licence (the atomcut-library mirror,
# one pack.json per pack with author, licence and the OpenGameArt page). Both are pinned to a commit and only the
# packs listed below are checked out (sparse + blobless clone), so the build is reproducible.
# Usage: tools/audio/fetch_sources.sh [cache dir]   (default ~/.cache/ventisca/audio_src)
set -euo pipefail
CACHE="${1:-${VENTISCA_AUDIO_SRC:-$HOME/.cache/ventisca/audio_src}}"
mkdir -p "$CACHE"

fetch() {  # fetch <dir> <repo url> <commit> <paths...>
  local name="$1" dir="$CACHE/$1" url="$2" commit="$3"; shift 3
  if [ -f "$dir/.done_$commit" ]; then echo "cached: $name @ ${commit:0:10}"; return; fi
  rm -rf "$dir"
  git clone -q --filter=blob:none --no-checkout "$url" "$dir"
  git -C "$dir" sparse-checkout init --no-cone
  git -C "$dir" sparse-checkout set "$@"
  git -C "$dir" checkout -q "$commit"
  touch "$dir/.done_$commit"
  echo "fetched: $name @ ${commit:0:10} ($(find "$dir" -type f -not -path '*/.git/*' | wc -l) files)"
}

# Kenney (kenney.nl, CC0 1.0) — mirror github.com/ETdoFresh/kenney.nl
fetch kenney https://github.com/ETdoFresh/kenney.nl 45df48c4d45f8716216b1a9e22df0b69cd9f5932 \
  "/kenney_impactsounds/" "/kenney_rpgaudio/" "/kenney_interfacesounds/" "/kenney_uiaudio/"

# OpenGameArt CC0 packs (pack.json: author, licence CC0-1.0, homepage) — github.com/novincode/atomcut-library
OGA=(42-snow-and-gravel-footsteps 9-wet-snow-steps zombies-sound-pack 80-cc0-creature-sfx 80-cc0-creture-sfx-2
  monster-sound-effects-2 monster-sound-effects-pack monster-sound-pack-volume-1 100-cc0-metal-and-wood-sfx
  75-cc0-breaking-falling-hit-sfx 35-wooden-crackshitsdestructions door-open-door-close door-open-door-close-set
  swishes-sound-pack 37-hitspunches 8-wet-squish-slurp-impacts hurt-death-sound-effect-for-character
  15-vocal-male-strainhurtpainjump-sounds 30-cc0-sfx-loops footsteps-leather-cloth-armor
  different-steps-on-wood-stone-leaves-gravel-and-mud 25-cc0-bang-firework-sfx wood-and-metal-sound-effects-volume-2
  5-hit-sounds-dying male-gruntyelling-sounds 100-cc0-sfx 100-cc0-sfx-2 202-more-sound-effects
  fantozzis-footsteps-grasssand-stone 40-cc0-water-splash-slime-sfx 20-rustles-dry-leaves rpg-sound-pack
  swish-bamboo-stick-weapon-swhoshes 20-sword-sound-effects-attacks-and-clashes racing-car-engine-sound-loops)
paths=()
for p in "${OGA[@]}"; do paths+=("/packs/opengameart-$p/"); done
fetch oga https://github.com/novincode/atomcut-library 391f87ff50bdad7645f9007708fef8ff07c8a00a "${paths[@]}"
echo "audio sources in $CACHE"
