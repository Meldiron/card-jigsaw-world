# Pure-Python BlurHash encoder (https://blurha.sh), 4x3 components.
import math
from PIL import Image

ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"

def _b83(value, length):
    out = ''
    for i in range(1, length + 1):
        digit = (value // (83 ** (length - i))) % 83
        out += ALPHABET[digit]
    return out

def _srgb_to_linear(v):
    v = v / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

def _linear_to_srgb(v):
    v = max(0.0, min(1.0, v))
    return int(round((v * 12.92 if v <= 0.0031308 else 1.055 * (v ** (1 / 2.4)) - 0.055) * 255))

def _sign_pow(v, e):
    return math.copysign(abs(v) ** e, v)

_LIN = [_srgb_to_linear(i) for i in range(256)]

def encode(img, cx=4, cy=3):
    img = img.convert('RGB')
    img.thumbnail((48, 48))
    w, h = img.size
    px = img.load()
    lin = [[(_LIN[px[x, y][0]], _LIN[px[x, y][1]], _LIN[px[x, y][2]]) for x in range(w)] for y in range(h)]
    cosx = [[math.cos(math.pi * i * x / w) for x in range(w)] for i in range(cx)]
    cosy = [[math.cos(math.pi * j * y / h) for y in range(h)] for j in range(cy)]
    comps = []
    for j in range(cy):
        for i in range(cx):
            norm = 1.0 if (i == 0 and j == 0) else 2.0
            r = g = b = 0.0
            for y in range(h):
                cy_ = cosy[j][y]
                row = lin[y]
                cx_row = cosx[i]
                for x in range(w):
                    basis = cx_row[x] * cy_
                    pr, pg, pb = row[x]
                    r += basis * pr; g += basis * pg; b += basis * pb
            scale = norm / (w * h)
            comps.append((r * scale, g * scale, b * scale))
    dc = comps[0]; ac = comps[1:]
    hash_ = _b83((cx - 1) + (cy - 1) * 9, 1)
    if ac:
        max_val = max(abs(c) for comp in ac for c in comp)
        q = max(0, min(82, int(math.floor(max_val * 166 - 0.5))))
        max_val = (q + 1) / 166.0
        hash_ += _b83(q, 1)
    else:
        max_val = 1.0
        hash_ += _b83(0, 1)
    hash_ += _b83((_linear_to_srgb(dc[0]) << 16) + (_linear_to_srgb(dc[1]) << 8) + _linear_to_srgb(dc[2]), 4)
    for r, g, b in ac:
        qr = max(0, min(18, int(math.floor(_sign_pow(r / max_val, 0.5) * 9 + 9.5))))
        qg = max(0, min(18, int(math.floor(_sign_pow(g / max_val, 0.5) * 9 + 9.5))))
        qb = max(0, min(18, int(math.floor(_sign_pow(b / max_val, 0.5) * 9 + 9.5))))
        hash_ += _b83(qr * 19 * 19 + qg * 19 + qb, 2)
    return hash_
