"""Read skinned glTF (.glb) files the way a game engine plays them: node hierarchy, rest TRS, skins, and
animation samplers (LINEAR / STEP / CUBICSPLINE) evaluated at any time, with forward kinematics.

Used by verify_chars.py (ASSET_SPEC_V2 §7) so that bone names, loops, durations and the foot metrics are
measured on the exported file, not on the Blender scene that produced it. Coordinates are glTF's (Y up,
+Z = model front); `blender_to_gltf((x, y, z)) = (x, z, -y)`.
"""
import json
import struct

from mathutils import Matrix, Quaternion, Vector

_COMP = {5126: ("f", 4), 5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5120: ("b", 1), 5122: ("h", 2)}
_NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def blender_to_gltf(p):
    return Vector((p[0], p[2], -p[1]))


class Glb:
    def __init__(self, path):
        b = open(path, "rb").read()
        if b[:4] != b"glTF":
            raise ValueError("%s is not a binary glTF" % path)
        n = struct.unpack_from("<I", b, 12)[0]
        self.json = json.loads(b[20:20 + n])
        off = 20 + n
        self.bin = b""
        if off + 8 <= len(b):
            blen = struct.unpack_from("<I", b, off)[0]
            self.bin = b[off + 8:off + 8 + blen]
        self.nodes = self.json.get("nodes", [])
        self.parent = {}
        for i, nd in enumerate(self.nodes):
            for c in nd.get("children", []):
                self.parent[c] = i
        self.by_name = {nd.get("name"): i for i, nd in enumerate(self.nodes)}

    def accessor(self, idx, normalized=None):
        """List of tuples (raw integers unless `normalized` or the accessor says so)."""
        acc = self.json["accessors"][idx]
        bv = self.json["bufferViews"][acc["bufferView"]]
        fmt, size = _COMP[acc["componentType"]]
        nc = _NCOMP[acc["type"]]
        stride = bv.get("byteStride", size * nc)
        off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        norm = acc.get("normalized", False) if normalized is None else normalized
        scale = {"B": 255.0, "H": 65535.0, "b": 127.0, "h": 32767.0}.get(fmt) if norm else None
        out = []
        for i in range(acc["count"]):
            vals = struct.unpack_from("<%d%s" % (nc, fmt), self.bin, off + i * stride)
            out.append(tuple(v / scale for v in vals) if scale else vals)
        return out

    # -- rest pose ---------------------------------------------------------------------------------
    def rest_local(self, i):
        nd = self.nodes[i]
        if "matrix" in nd:
            m = nd["matrix"]
            return Matrix([m[0:4], m[4:8], m[8:12], m[12:16]]).transposed()
        t = Vector(nd.get("translation", (0, 0, 0)))
        r = nd.get("rotation", (0, 0, 0, 1))
        s = nd.get("scale", (1, 1, 1))
        return trs(t, Quaternion((r[3], r[0], r[1], r[2])), s)

    def global_of(self, i, local_fn):
        m = local_fn(i)
        while i in self.parent:
            i = self.parent[i]
            m = local_fn(i) @ m
        return m

    def rest_global(self, i):
        return self.global_of(i, self.rest_local)

    # -- animations ---------------------------------------------------------------------------------
    def animations(self):
        return {a["name"]: a for a in self.json.get("animations", [])}

    def channels(self, anim):
        """{(node, path): (times, values, interpolation)}"""
        out = {}
        for ch in anim["channels"]:
            smp = anim["samplers"][ch["sampler"]]
            times = [t[0] for t in self.accessor(smp["input"])]
            vals = self.accessor(smp["output"], normalized=True if self._is_int(smp["output"]) else False)
            out[(ch["target"]["node"], ch["target"]["path"])] = (times, vals, smp.get("interpolation", "LINEAR"))
        return out

    def _is_int(self, idx):
        return self.json["accessors"][idx]["componentType"] != 5126

    def duration(self, anim):
        return max(self.accessor(s["input"])[-1][0] for s in anim["samplers"])


def trs(t, q, s):
    return Matrix.Translation(t) @ q.to_matrix().to_4x4() @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))


def _sample(times, vals, interp, t, path):
    n = len(times)
    cubic = interp == "CUBICSPLINE"

    def val(k):
        return vals[3 * k + 1] if cubic else vals[k]
    if t <= times[0] or n == 1:
        v = val(0)
    elif t >= times[-1]:
        v = val(n - 1)
    else:
        k = 0
        lo, hi = 0, n - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if times[mid] <= t:
                lo = mid
            else:
                hi = mid
        k = lo
        t0, t1 = times[k], times[k + 1]
        u = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
        if interp == "STEP":
            v = val(k)
        elif cubic:
            dt = t1 - t0
            p0, m0 = Vector(vals[3 * k + 1]), Vector(vals[3 * k + 2]) * dt
            p1, m1 = Vector(vals[3 * (k + 1) + 1]), Vector(vals[3 * (k + 1)]) * dt
            u2, u3 = u * u, u * u * u
            v = tuple((2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * m0 + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * m1)
        elif path == "rotation":
            a, b = vals[k], vals[k + 1]
            qa = Quaternion((a[3], a[0], a[1], a[2]))
            qb = Quaternion((b[3], b[0], b[1], b[2]))
            q = qa.slerp(qb, u)
            v = (q.x, q.y, q.z, q.w)
        else:
            a, b = vals[k], vals[k + 1]
            v = tuple(a[c] + (b[c] - a[c]) * u for c in range(len(a)))
    if path == "rotation":
        q = Quaternion((v[3], v[0], v[1], v[2]))
        q.normalize()
        return q
    return Vector(v)


class Player:
    """Evaluates one animation of a Glb at time t (node-local matrices, then FK)."""

    def __init__(self, glb, anim_name):
        self.g = glb
        self.anim = glb.animations()[anim_name]
        self.ch = glb.channels(self.anim)
        self.duration = glb.duration(self.anim)
        self._t = None
        self._cache = {}

    def local(self, i):
        nd = self.g.nodes[i]
        if (i, "translation") not in self.ch and (i, "rotation") not in self.ch and (i, "scale") not in self.ch:
            return self.g.rest_local(i)
        t = Vector(nd.get("translation", (0, 0, 0)))
        r = nd.get("rotation", (0, 0, 0, 1))
        q = Quaternion((r[3], r[0], r[1], r[2]))
        s = Vector(nd.get("scale", (1, 1, 1)))
        if (i, "translation") in self.ch:
            t = _sample(*self.ch[(i, "translation")], self._t, "translation")
        if (i, "rotation") in self.ch:
            q = _sample(*self.ch[(i, "rotation")], self._t, "rotation")
        if (i, "scale") in self.ch:
            s = _sample(*self.ch[(i, "scale")], self._t, "scale")
        return trs(t, q, s)

    def at(self, t):
        self._t = t
        self._cache = {}
        return self

    def global_(self, i):
        if i in self._cache:
            return self._cache[i]
        m = self.local(i)
        if i in self.g.parent:
            m = self.global_(self.g.parent[i]) @ m
        self._cache[i] = m
        return m

    def channel_values(self, i, path):
        return self.ch.get((i, path))
