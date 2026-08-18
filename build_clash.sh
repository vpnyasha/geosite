#!/usr/bin/env bash
# =============================================================================
# build_clash.sh — конвертирует плоские списки data/ в rule-set'ы Mihomo/Clash.
#
# Зачем: Mihomo не читает geosite.dat, зато умеет rule-providers по HTTP. Списки
# те же самые, отличается только запись правил, поэтому конвертер, а не второй
# источник правды.
#
# behavior: classical — единственный формат, который переваривает все четыре типа
# наших записей (domain / full / keyword / regexp). behavior: domain отбросил бы
# keyword:xn--p1ai, то есть всю зону .рф.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$HERE/data}"
OUT="${OUT:-$HERE/clash}"
mkdir -p "$OUT"

for src in "$SRC"/*; do
  name="$(basename "$src")"
  awk -F: '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1 == "domain"  { sub(/^domain:/,  ""); print "DOMAIN-SUFFIX,"  $0; next }
    $1 == "full"    { sub(/^full:/,    ""); print "DOMAIN,"         $0; next }
    $1 == "keyword" { sub(/^keyword:/, ""); print "DOMAIN-KEYWORD," $0; next }
    $1 == "regexp"  { sub(/^regexp:/,  ""); print "DOMAIN-REGEX,"   $0; next }
  ' "$src" > "$OUT/$name.list"
  printf "%-18s %6d rules\n" "$name.list" "$(wc -l < "$OUT/$name.list")"
done

# Пустой rule-set молча выключил бы целую категорию у всех Mihomo-клиентов.
for f in "$OUT"/*.list; do
  test -s "$f" || { echo "!! пустой rule-set: $f" >&2; exit 1; }
done
