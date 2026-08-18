#!/usr/bin/env python3
"""build_geoip.py — собирает компактный geoip.dat из готовых списков runetfreedom.

Зачем: правила по доменам не ловят трафик, где домена нет — голос Discord по UDP,
дата-центры Telegram, игры. Нужен список адресов заблокированного.

Берём у runetfreedom/russia-v2ray-rules-dat (2233★, ежедневная сборка) только те
категории, что нам нужны, и пересобираем свой файл: их полный geoip — 18 МБ, столько
мобильный клиент качать не должен.

Категории на выходе:
  blocked  — адреса заблокированных в РФ ресурсов  → в туннель
  ru       — российские сети                        → напрямую
  private  — локальные сети                         → напрямую
"""

import pathlib
import urllib.request

SRC = "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat"
WANT = {"RU-BLOCKED": "blocked", "RU": "ru", "PRIVATE": "private"}
OUT = pathlib.Path(__file__).parent / "geoip.dat"

# Дописываем руками то, чего нет в источнике. Голосовые серверы Discord ходят по UDP
# на собственные сети — домена в таком пакете нет, и правило по домену его не поймает.
# Discord в РФ заблокирован, значит голос обязан идти в туннель, иначе он просто молчит.
CURATED = {
    "blocked": [
        ("66.22.192.0", 18),    # Discord voice (AS49544)
        ("66.22.196.0", 22),    # Discord voice
    ],
}


def read_varint(b, i):
    r = s = 0
    while True:
        x = b[i]; i += 1
        r |= (x & 0x7f) << s; s += 7
        if not x & 0x80:
            return r, i


def read_fields(b):
    i = 0
    while i < len(b):
        key, i = read_varint(b, i)
        field, wire = key >> 3, key & 7
        if wire == 2:
            n, i = read_varint(b, i)
            yield field, b[i:i+n]; i += n
        elif wire == 0:
            v, i = read_varint(b, i)
            yield field, v
        else:
            raise ValueError(f"неподдерживаемый wire type {wire}")


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7f
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def tag(field, wire):
    return varint((field << 3) | wire)


def blob(field, data):
    return tag(field, 2) + varint(len(data)) + data


print(f">> качаю {SRC}")
with urllib.request.urlopen(SRC, timeout=300) as r:
    raw = r.read()
print(f"   {len(raw)/1024/1024:.1f} МБ")

out = bytearray()
found = {}
for f, v in read_fields(raw):
    if f != 1:
        continue
    name = None
    cidrs = []
    for f2, v2 in read_fields(v):
        if f2 == 1:
            name = v2.decode()
        elif f2 == 2:
            cidrs.append(v2)
    if name in WANT:
        ours = WANT[name]
        extra = []
        for addr, prefix in CURATED.get(ours, []):
            octets = bytes(int(x) for x in addr.split("."))
            extra.append(blob(1, octets) + tag(2, 0) + varint(prefix))
        entry = blob(1, ours.encode()) + b"".join(blob(2, c) for c in cidrs + extra)
        out += blob(1, entry)
        found[ours] = len(cidrs) + len(extra)

missing = set(WANT.values()) - set(found)
if missing:
    raise SystemExit(f"!! в источнике нет категорий: {sorted(missing)} — сборка отменена")

OUT.write_bytes(bytes(out))
for name, cnt in found.items():
    print(f"   geoip:{name:8} {cnt:>7} сетей")
print(f">> {OUT.name}: {len(out)/1024:.0f} КБ (из {len(raw)/1024/1024:.0f} МБ исходных)")
