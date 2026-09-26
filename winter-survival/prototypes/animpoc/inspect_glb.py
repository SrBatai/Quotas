import json, struct, sys
def load(path):
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 12)[0]
    return json.loads(b[20:20 + n])
for path in sys.argv[1:]:
    g = load(path)
    print("==", path)
    print(" nodes:", len(g["nodes"]), "skins:", [(s.get("name"), len(s["joints"])) for s in g.get("skins", [])])
    print(" meshes:", [(m["name"], len(m["primitives"]), sorted(m["primitives"][0]["attributes"].keys())) for m in g["meshes"]])
    for a in g.get("animations", []):
        paths = {}
        for c in a["channels"]:
            paths[c["target"]["path"]] = paths.get(c["target"]["path"], 0) + 1
        mx = max(g["accessors"][s["input"]]["max"][0] for s in a["samplers"])
        print("  anim %-22s channels=%s duration=%.3fs" % (a["name"], paths, mx))
