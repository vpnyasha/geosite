#!/usr/bin/env bash
# =============================================================================
# build_sources.sh — harvest upstream public domain lists and (re)generate the
# plaintext category source files under data/ (v2fly domain-list-community format).
#
# Self-contained & reproducible: run locally or in CI. Requires: bash, curl, awk,
# grep, sort, sed.  Output dir overridable via $OUT (default: ./data next to this
# script).  Harvest cache dir overridable via $CACHE (default: a temp dir).
#
# Categories produced:
#   our-whitelist   our-category-ru   our-geoblock-ru
#   our-ads         our-winspy        our-torrent
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-$HERE/data}"
CACHE="${CACHE:-$(mktemp -d)}"
mkdir -p "$OUT" "$CACHE"

RCV="$CACHE/rcv"; LOY="$CACHE/loyal"; V2="$CACHE/v2fly"
mkdir -p "$RCV" "$LOY" "$V2"

echo ">> Cache: $CACHE"
echo ">> Output: $OUT"

# ---- helpers ---------------------------------------------------------------
# Newline-safe concat: awk 1 guarantees trailing newline per file (prevents the
# last line of one source gluing onto the first line of the next).
catnl() { awk 1 "$@"; }
# Keep only valid v2fly directive lines, dedup.
norm() { grep -E '^(domain|full|keyword|regexp):' | sort -u; }
# Flatten v2fly leaf lists: drop comments/blank/include, strip "@attr" tags,
# prefix bare domains with "domain:".
flatten_bare() {
  awk '
    /^[[:space:]]*#/ {next} /^[[:space:]]*$/ {next}
    { line=$0; sub(/[[:space:]]+@.*$/,"",line); sub(/[[:space:]]+$/,"",line)
      if (line ~ /^(domain|full|keyword|regexp):/) {print line; next}
      if (line ~ /^include:/) next
      if (line=="") next
      print "domain:" line }'
}
fetch() { # fetch URL DEST
  curl -fsSL "$1" -o "$2" && echo "   ok $(basename "$2") ($(wc -l < "$2") lines)" \
    || { echo "   FAIL $1" >&2; return 1; }
}

# ---- harvest ---------------------------------------------------------------
echo ">> Harvest roscomvpn"
RB="https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data"
for f in whitelist category-ru category-geoblock-ru torrent win-spy category-ads; do
  fetch "$RB/$f" "$RCV/$f" || true
done

echo ">> Harvest Loyalsoldier (win-spy)"
LB="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release"
fetch "$LB/win-spy.txt" "$LOY/loyal-win-spy.txt" || true

echo ">> Harvest v2fly domain-list-community"
VB="https://raw.githubusercontent.com/v2fly/domain-list-community/master/data"
fetch "$VB/category-public-tracker" "$V2/v2-public-tracker" || true
fetch "$VB/category-ads-all"        "$V2/v2-category-ads-all" || true
for f in openx pubmatic taboola segment adjust ogury supersonic growingio clearbit; do
  fetch "$VB/$f" "$V2/v2-ad-$f" || true
done

# =============================================================================
# 1. our-geoblock-ru  — CHERRY-PICK: ONLY the Russian side.
# -----------------------------------------------------------------------------
# roscomvpn category-geoblock-ru is explicitly two-part, separated by the marker
# "Зарубежные сайты ...":
#   * BEFORE marker = Russian sites that geo-fence RU IPs        -> KEEP (direct)
#   * AFTER  marker = foreign brands that geo-fence RU IPs       -> DROP
# The foreign brands (Adobe, OpenAI, Spotify, Behance(adobe), arkoselabs,
# crashlytics, ftcdn, Netflix, Claude, ...) need a FOREIGN exit, so they must
# fall through to default (proxy), NOT go direct. We therefore exclude them.
#
# Heuristic:
#   PRIMARY  = section position (RU block only).
#   SECONDARY (safety net) = rescue any *.ru/*.su/*.рф(xn--p1ai) domains that may
#     sit in the foreign block, MINUS a deny-list of foreign services that merely
#     use a .su/.ru-looking TLD but are NOT Russian (happ.su = proxy client,
#     kemono.su = foreign content aggregator). TLD alone is NOT trusted.
#   PLUS our own curated critical RU services (banks/NSPK/gov/marketplaces/media)
#     that must use a RU IP.
# =============================================================================
MARK=$(grep -n 'Зарубежные сайты' "$RCV/category-geoblock-ru" | head -1 | cut -d: -f1)
RU_END=$((MARK - 1))
sed -n "1,${RU_END}p"   "$RCV/category-geoblock-ru" | norm > "$CACHE/gb_ru_primary.txt"
sed -n "${MARK},\$p"    "$RCV/category-geoblock-ru"        > "$CACHE/gb_foreign.txt"

NOT_RU='happ\.su|kemono\.su'
grep -E '^(domain|full|keyword|regexp):' "$CACHE/gb_foreign.txt" \
  | grep -E '\.(ru|su)($)|xn--p1ai|xn--' | grep -vE "$NOT_RU" | sort -u \
  > "$CACHE/gb_ru_rescued.txt" || true

cat > "$CACHE/gb_ru_curated.txt" <<'EOF'
# Banks (geo-fence foreign IPs)
domain:alfabank.ru
domain:alfabank.com
domain:vtb.ru
domain:gazprombank.ru
domain:psbank.ru
domain:rshb.ru
domain:tbank.ru
domain:tinkoff.ru
domain:sberbank.ru
domain:sber.ru
domain:sberbank.com
domain:tochka.com
# NSPK / Mir / MirPay
domain:nspk.ru
domain:mironline.ru
domain:privetmir.ru
domain:mirconnect.ru
# Gov / tax / CB / mos.ru
domain:gosuslugi.ru
domain:nalog.ru
domain:nalog.gov.ru
domain:cbr.ru
domain:mos.ru
domain:government.ru
domain:gov.ru
# Marketplaces / classifieds
domain:ozon.ru
domain:wildberries.ru
domain:wb.ru
domain:magnit.ru
domain:x5.ru
domain:avito.ru
# Media (geo-fenced)
domain:kinopoisk.ru
domain:hd.kinopoisk.ru
EOF

catnl "$CACHE/gb_ru_primary.txt" "$CACHE/gb_ru_rescued.txt" "$CACHE/gb_ru_curated.txt" \
  | norm > "$OUT/our-geoblock-ru"

# =============================================================================
# 2. our-whitelist  — RU on foreign CDN + critical RU services + IDN .рф
# =============================================================================
cat > "$CACHE/wl_curated.txt" <<'EOF'
# IDN .рф catch-all (Punycode)
keyword:xn--p1ai
# Banks needing RU IP
domain:alfabank.ru
domain:vtb.ru
domain:gazprombank.ru
domain:psbank.ru
domain:rshb.ru
domain:tbank.ru
domain:tinkoff.ru
domain:sberbank.ru
domain:sber.ru
domain:tochka.com
# NSPK / MirPay
domain:nspk.ru
domain:mironline.ru
domain:privetmir.ru
domain:mirpay.ru
# Gov / tax / CB / mos.ru / gosuslugi
domain:gosuslugi.ru
domain:nalog.ru
domain:nalog.gov.ru
domain:cbr.ru
domain:mos.ru
# Marketplaces
domain:ozon.ru
domain:ozon.com
domain:wildberries.ru
domain:wb.ru
domain:magnit.ru
domain:magnit.com
domain:x5.ru
domain:5ka.ru
domain:perekrestok.ru
domain:avito.ru
domain:avito.st
# Telecom
domain:mts.ru
domain:megafon.ru
domain:beeline.ru
domain:tele2.ru
domain:t2.ru
domain:yota.ru
# Media
domain:rbc.ru
domain:lenta.ru
domain:kommersant.ru
# Exchange
domain:moex.com
# Streaming
domain:kinopoisk.ru
domain:okko.tv
domain:wink.ru
# VK / Mail / Yandex clusters
domain:vk.com
domain:vk.ru
domain:vkontakte.ru
domain:userapi.com
domain:vk-cdn.net
domain:vkuservideo.net
domain:mail.ru
domain:list.ru
domain:bk.ru
domain:inbox.ru
domain:yandex.ru
domain:yandex.net
domain:ya.ru
domain:yandex.com
domain:yastatic.net
domain:yandex.st
EOF
catnl "$RCV/whitelist" "$CACHE/wl_curated.txt" | norm > "$OUT/our-whitelist"

# =============================================================================
# 3. our-category-ru  — broad RU coverage (category-ru + whitelist + geoblock RU)
# =============================================================================
catnl "$RCV/category-ru" "$OUT/our-whitelist" "$OUT/our-geoblock-ru" | norm > "$OUT/our-category-ru"

# =============================================================================
# 4. our-ads  — curated ad/tracking networks (kept lean for routing, not a
#               167k-line DNS blocklist). roscomvpn ads + v2fly leaves + curated.
# =============================================================================
# SEARCH-ENGINE EXCLUSION: never block ad/analytics domains of search engines
# (Google / Yandex / Mail.ru). Blocking them makes the browser look non-human to
# those engines -> more "your computer is sending automated queries" CAPTCHAs, and
# adds no real value. We still block 3rd-party ad/tracking networks. Applied to
# ALL upstream ad sources so a re-harvest can never reintroduce them.
SEARCH_EXCLUDE='google|gstatic|doubleclick|2mdn|googleapis|ggpht|googleusercontent|yandex|adfox|mail\.ru'

cat > "$CACHE/ads_curated.txt" <<'EOF'
domain:scorecardresearch.com
domain:criteo.com
domain:criteo.net
domain:outbrain.com
domain:taboola.com
domain:adsrvr.org
domain:rubiconproject.com
domain:pubmatic.com
domain:openx.net
domain:adnxs.com
domain:appnexus.com
domain:adcolony.com
domain:applovin.com
domain:unityads.unity3d.com
domain:chartboost.com
domain:vungle.com
domain:inmobi.com
domain:moatads.com
domain:branch.io
domain:adjust.com
domain:appsflyer.com
domain:amplitude.com
domain:mixpanel.com
domain:segment.com
domain:hotjar.com
domain:fullstory.com
domain:counter.yadro.ru
domain:mgid.com
domain:propellerads.com
EOF
{ catnl "$RCV/category-ads" "$CACHE/ads_curated.txt";
  catnl "$V2/v2-category-ads-all" 2>/dev/null | flatten_bare;
  catnl "$V2"/v2-ad-* 2>/dev/null | flatten_bare; } \
  | norm | grep -vE "$SEARCH_EXCLUDE" > "$OUT/our-ads"

# =============================================================================
# 5. our-winspy  — Windows telemetry (roscomvpn + Loyalsoldier, deduped)
# =============================================================================
{ catnl "$RCV/win-spy"; catnl "$LOY/loyal-win-spy.txt" | flatten_bare; } \
  | norm > "$OUT/our-winspy"

# =============================================================================
# 6. our-torrent  — trackers/DHT (roscomvpn + v2fly public-tracker, deduped)
# =============================================================================
catnl "$RCV/torrent" "$V2/v2-public-tracker" | norm > "$OUT/our-torrent"

# ---- report ----------------------------------------------------------------
echo
echo "=== CATEGORY COUNTS ==="
for f in our-whitelist our-category-ru our-geoblock-ru our-ads our-winspy our-torrent; do
  printf "%-18s %6d entries\n" "$f" "$(wc -l < "$OUT/$f")"
done
echo
echo "Safety check: foreign services must NOT appear in our-geoblock-ru:"
if grep -iqE 'adobe|openai|chatgpt|spotify|behance|arkoselabs|crashlytics|ftcdn|netflix|claude|anthropic' "$OUT/our-geoblock-ru"; then
  echo "!! LEAK DETECTED in our-geoblock-ru" >&2; exit 1
else
  echo "ok — no foreign-block services in our-geoblock-ru"
fi
