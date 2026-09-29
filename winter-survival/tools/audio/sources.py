"""CC0 source recordings for the S1 sound build (fetched by tools/audio/fetch_sources.sh).

`use(pack, file)` returns the local path of one recording and records its provenance (author, licence, page), so
build_audio.py can write assets/audio/LICENSES.md with every recording each shipped file was made from.
Only CC0 1.0 material is allowed here: Kenney's packs (kenney.nl, License.txt "Creative Commons Zero, CC0") and
OpenGameArt packs published under CC0 (pack.json "license": "CC0-1.0"). Anything else fails the build.
"""
from __future__ import annotations

import json
import os

CACHE = os.environ.get("VENTISCA_AUDIO_SRC", os.path.expanduser("~/.cache/ventisca/audio_src"))

KENNEY_MIRROR = "https://github.com/ETdoFresh/kenney.nl (commit 45df48c4)"
OGA_MIRROR = "https://github.com/novincode/atomcut-library (commit 391f87ff)"
KENNEY_PAGES = {
    "kenney_impactsounds": ("Impact Sounds", "https://kenney.nl/assets/impact-sounds"),
    "kenney_rpgaudio": ("RPG Audio", "https://kenney.nl/assets/rpg-audio"),
    "kenney_interfacesounds": ("Interface Sounds", "https://kenney.nl/assets/interface-sounds"),
    "kenney_uiaudio": ("UI Audio", "https://kenney.nl/assets/ui-audio"),
}

# every recording used by the current build: id -> {path, pack, author, license, url}
USED: dict[str, dict] = {}
# recordings `use()`d since the last file was written (build_audio.Build.out attributes them to that file)
CURRENT: list[str] = []


class SourceError(RuntimeError):
    pass


def _oga_meta(pack: str) -> dict:
    pj = os.path.join(CACHE, "oga", "packs", "opengameart-" + pack, "pack.json")
    if not os.path.exists(pj):
        raise SourceError(f"missing OGA pack {pack}: run tools/audio/fetch_sources.sh")
    with open(pj, encoding="utf-8") as f:
        d = json.load(f)
    if d.get("license") != "CC0-1.0":
        raise SourceError(f"{pack}: licence {d.get('license')} is not CC0-1.0")
    return d


def use(pack: str, file: str) -> str:
    """pack = 'kenney_impactsounds' … or an OpenGameArt slug ('zombies-sound-pack'); file = name in the pack."""
    if pack.startswith("kenney_"):
        sub = "Audio"
        path = os.path.join(CACHE, "kenney", pack, sub, file)
        lic_path = os.path.join(CACHE, "kenney", pack, "License.txt")
        if not os.path.exists(lic_path):
            raise SourceError(f"missing {lic_path}: run tools/audio/fetch_sources.sh")
        with open(lic_path, encoding="utf-8", errors="replace") as f:
            if "CC0" not in f.read():
                raise SourceError(f"{pack}: License.txt is not CC0")
        title, url = KENNEY_PAGES[pack]
        meta = {"pack": f"Kenney — {title}", "author": "Kenney (kenney.nl)", "license": "CC0 1.0", "url": url,
                "mirror": KENNEY_MIRROR}
    else:
        d = _oga_meta(pack)
        path = os.path.join(CACHE, "oga", "packs", "opengameart-" + pack, "audio", file)
        meta = {"pack": d.get("title", pack), "author": d.get("publisher", {}).get("name", "?") + " (OpenGameArt)",
                "license": "CC0 1.0", "url": d.get("homepage", ""), "mirror": OGA_MIRROR}
    if not os.path.exists(path):
        raise SourceError(f"missing source file {path}")
    key = f"{pack}/{file}"
    USED[key] = dict(meta, file=file, path=path)
    CURRENT.append(key)
    return path


def glob_pack(pack: str, prefix: str = "", suffix: str = "") -> list[str]:
    if pack.startswith("kenney_"):
        d = os.path.join(CACHE, "kenney", pack, "Audio")
    else:
        d = os.path.join(CACHE, "oga", "packs", "opengameart-" + pack, "audio")
    if not os.path.isdir(d):
        raise SourceError(f"missing pack dir {d}")
    return sorted(f for f in os.listdir(d) if f.startswith(prefix) and f.endswith(suffix))
