"""Pinned download of the third-party (CC0) source files of milestone A1 into a cache OUTSIDE the repository.

    cd winter-survival/blender
    python3 third_party/fetch.py              # fetch what is missing from the cache, verify every SHA-256 (exit 0 = OK)
    python3 third_party/fetch.py --verify     # offline: verify the cache against sources.json (no network)
    python3 third_party/fetch.py --lock       # adding a pack: record sha256 / bytes of entries whose sha256 is null
    python3 third_party/fetch.py --list       # pack, file, bytes, cache path
    python3 third_party/fetch.py --packs kenney-car-kit,quaternius-cars      # restrict to some packs

`sources.json` (next to this file) is the lock: every source repository is pinned to a COMMIT, every file carries
its SHA-256 and size. Nothing is cloned: files are plain HTTPS GETs at the pinned commit on
  raw.githubusercontent.com/<repo>/<commit>/<path>          (git blobs; for Git LFS files: the LFS pointer)
  media.githubusercontent.com/media/<repo>/<commit>/<path>  (Git LFS content)
Git LFS files are verified twice: the content's SHA-256 must equal the pointer's `oid sha256` (the hash the git tree
at that commit records, i.e. the upstream author's file) AND the hash in sources.json.

Cache: $VENTISCA_TP_CACHE or ~/.cache/ventisca/third_party, laid out <cache>/<source>/<commit>/<repo path> so that
relative references inside the models (GLB -> Textures/colormap.png, USDA -> ./textures/*.png) resolve. The cache is
never inside the repository and is never committed; delete it at will and re-run this script.

Used by build_city.py through `pack_file(pack, rel)` (fetches on demand and verifies once per process).
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCES_JSON = HERE / "sources.json"
RAW = "https://raw.githubusercontent.com/%s/%s/%s"
MEDIA = "https://media.githubusercontent.com/media/%s/%s/%s"
LFS_MAGIC = b"version https://git-lfs.github.com/spec/v1"

_SOURCES = None
_VERIFIED = set()


def cache_root():
    env = os.environ.get("VENTISCA_TP_CACHE")
    root = Path(env).expanduser() if env else Path.home() / ".cache" / "ventisca" / "third_party"
    repo = HERE.parents[1]                     # winter-survival/
    try:
        root.resolve().relative_to(repo.resolve())
        raise RuntimeError("the third-party cache %s must not be inside the repository" % root)
    except ValueError:
        pass
    return root


def load_sources(reload=False):
    global _SOURCES
    if _SOURCES is None or reload:
        _SOURCES = json.loads(SOURCES_JSON.read_text())
    return _SOURCES


def save_sources(data):
    SOURCES_JSON.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")


def repo_path(pack, rel):
    p = load_sources()["packs"][pack]
    return "%s/%s" % (p["root"], rel) if p.get("root") else rel


def local_path(pack, rel):
    s = load_sources()
    p = s["packs"][pack]
    src = s["sources"][p["source"]]
    return cache_root() / p["source"] / src["commit"] / repo_path(pack, rel)


def source_url(pack, rel, lfs=None):
    s = load_sources()
    p = s["packs"][pack]
    src = s["sources"][p["source"]]
    quoted = urllib.parse.quote(repo_path(pack, rel))
    if lfs is None:
        lfs = p["files"][rel].get("lfs", False)
    return (MEDIA if lfs else RAW) % (src["repo"], src["commit"], quoted)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def _get(url, tries=4):
    last = None
    for k in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=90) as r:
                return r.read()
        except Exception as ex:           # transient proxy resets: retry with a back-off
            last = ex
            time.sleep(1.5 * (k + 1))
    raise RuntimeError("download failed: %s (%s)" % (url, last))


def _parse_pointer(data):
    oid = size = None
    for line in data.decode("utf-8", "replace").splitlines():
        if line.startswith("oid sha256:"):
            oid = line.split(":", 1)[1].strip()
        elif line.startswith("size "):
            size = int(line.split()[1])
    return oid, size


def download(pack, rel):
    """Download one file at the pinned commit. Returns (bytes, lfs, pointer_oid or None)."""
    s = load_sources()
    src = s["sources"][s["packs"][pack]["source"]]
    raw = _get(source_url(pack, rel, lfs=False))
    if raw.startswith(LFS_MAGIC):
        oid, size = _parse_pointer(raw)
        data = _get(source_url(pack, rel, lfs=True))
        if sha256(data) != oid or (size is not None and len(data) != size):
            raise RuntimeError("%s/%s: LFS content does not match its pointer (oid %s)" % (pack, rel, oid))
        return data, True, oid
    if src.get("lfs_only"):
        raise RuntimeError("%s/%s: expected a Git LFS pointer" % (pack, rel))
    return raw, False, None


def verify_file(pack, rel):
    """Problems of the cached copy of one file (empty list = OK)."""
    ent = load_sources()["packs"][pack]["files"][rel]
    path = local_path(pack, rel)
    if not path.exists():
        return ["missing from the cache: %s" % path]
    data = path.read_bytes()
    out = []
    if ent.get("sha256") and sha256(data) != ent["sha256"]:
        out.append("%s/%s: sha256 %s != locked %s" % (pack, rel, sha256(data)[:12], ent["sha256"][:12]))
    if ent.get("bytes") is not None and len(data) != ent["bytes"]:
        out.append("%s/%s: %d bytes != locked %d" % (pack, rel, len(data), ent["bytes"]))
    return out


def fetch_file(pack, rel, lock=False):
    """Make sure the cached copy exists and matches the lock. With lock=True, record sha256/bytes of an entry whose
    sha256 is null. Returns 'cached' | 'fetched' | 'locked'."""
    ent = load_sources()["packs"][pack]["files"][rel]
    path = local_path(pack, rel)
    if path.exists() and ent.get("sha256") and not verify_file(pack, rel):
        return "cached"
    if not ent.get("sha256") and not lock:
        raise RuntimeError("%s/%s has no locked sha256: run fetch.py --lock" % (pack, rel))
    data, lfs, _oid = download(pack, rel)
    if ent.get("sha256"):
        if sha256(data) != ent["sha256"]:
            raise RuntimeError("%s/%s: downloaded sha256 %s != locked %s" % (pack, rel, sha256(data), ent["sha256"]))
        state = "fetched"
    else:
        ent["sha256"] = sha256(data)
        ent["bytes"] = len(data)
        ent["lfs"] = lfs
        state = "locked"
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".part")
    tmp.write_bytes(data)
    tmp.replace(path)
    return state


def reverse(path):
    """(pack, rel) of a cached file path, or None (used to record the textures a model pulled in)."""
    path = Path(path).resolve()
    s = load_sources()
    for pack, p in s["packs"].items():
        for rel in p["files"]:
            if local_path(pack, rel).resolve() == path:
                return pack, rel
    return None


def pack_file(pack, rel):
    """Cached, verified path of `rel` in `pack` (downloads it when missing). For the builders."""
    key = (pack, rel)
    if key not in _VERIFIED:
        if load_sources()["packs"][pack]["files"].get(rel) is None:
            raise KeyError("%s/%s is not in sources.json" % (pack, rel))
        fetch_file(pack, rel)
        probs = verify_file(pack, rel)
        if probs:
            raise RuntimeError("; ".join(probs))
        _VERIFIED.add(key)
    return local_path(pack, rel)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--verify", action="store_true", help="offline verification of the cache")
    ap.add_argument("--lock", action="store_true", help="record hashes of new (sha256 null) entries")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--packs", default="", help="comma-separated pack ids (default: all)")
    a = ap.parse_args(argv)
    s = load_sources()
    packs = [p for p in s["packs"] if not a.packs or p in a.packs.split(",")]
    print("cache: %s" % cache_root())
    problems, counts = [], {}
    for pack in packs:
        for rel in sorted(s["packs"][pack]["files"]):
            if a.list:
                ent = s["packs"][pack]["files"][rel]
                print("%-34s %-70s %9s %s" % (pack, rel, ent.get("bytes"), local_path(pack, rel)))
                continue
            if a.verify:
                pr = verify_file(pack, rel)
                problems += pr
                counts["ok" if not pr else "bad"] = counts.get("ok" if not pr else "bad", 0) + 1
                continue
            try:
                st = fetch_file(pack, rel, lock=a.lock)
                counts[st] = counts.get(st, 0) + 1
                if st != "cached":
                    print("%-8s %s/%s" % (st, pack, rel), flush=True)
            except Exception as ex:
                problems.append(str(ex))
    if a.lock:
        save_sources(s)
    if a.list:
        return 0
    print("files: %s" % ", ".join("%s %d" % kv for kv in sorted(counts.items())))
    for p in problems:
        print("FAIL %s" % p)
    print("ALL OK" if not problems else "%d FAILURES" % len(problems))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
