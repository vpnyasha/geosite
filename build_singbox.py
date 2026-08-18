#!/usr/bin/env python3
"""build_singbox.py — превращает списки data/ в rule-set'ы sing-box (формат source).

Sing-box не читает ни geosite.dat, ни clash-правила: у него свой rule-set. Списки те же,
меняется только запись, поэтому очередной конвертер, а не очередной источник правды.

ВАЖНО про domain_suffix: в sing-box это суффикс СТРОКИ, а не домена — "ozon.ru" поймает
заодно "myozon.ru". Поэтому наш `domain:x` (домен вместе с поддоменами) разворачивается
в пару: точное совпадение "x" + суффикс ".x".
"""

import json
import pathlib

HERE = pathlib.Path(__file__).parent
SRC = HERE / "data"
OUT = HERE / "singbox"
OUT.mkdir(exist_ok=True)

for src in sorted(SRC.iterdir()):
    rule: dict[str, list[str]] = {}
    for line in src.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        kind, value = line.split(":", 1)
        if kind == "domain":
            rule.setdefault("domain", []).append(value)
            rule.setdefault("domain_suffix", []).append("." + value)
        elif kind == "full":
            rule.setdefault("domain", []).append(value)
        elif kind == "keyword":
            rule.setdefault("domain_keyword", []).append(value)
        elif kind == "regexp":
            rule.setdefault("domain_regex", []).append(value)

    if not rule:
        raise SystemExit(f"!! пустой rule-set: {src.name}")

    (OUT / f"{src.name}.json").write_text(
        json.dumps({"version": 1, "rules": [rule]}, ensure_ascii=False) + "\n"
    )
    total = sum(len(v) for v in rule.values())
    print(f"{src.name + '.json':22} {total:6d} записей  {sorted(rule)}")
