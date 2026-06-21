# Custom geosite for xray routing (anti-censorship VPN, RU access)

Our own `geosite.dat` with project-specific categories, **self-hosted** — so the
runtime does not depend on a third-party repo (unlike Brava, which is wired to
`hydraponique/roscomvpn`). The plaintext sources in `data/` are the source of
truth; `geosite.dat` is compiled from them with
[`v2fly/domain-list-community`](https://github.com/v2fly/domain-list-community).

## Categories

| Category (`geosite:<name>`) | Purpose | Routing target | Entries |
|---|---|---|---|
| `our-whitelist`    | RU domains on **foreign CDNs** (geoip:ru misses them) + critical RU services needing a RU IP (banks, NSPK/MirPay, gov, marketplaces, telecom, media, MOEX, streaming, VK/Mail/Yandex) + IDN `.рф` | **DIRECT** | 472 |
| `our-category-ru`  | Broad enriched RU domain set | **DIRECT** | 528 |
| `our-geoblock-ru`  | **RU side only** — RU services that geo-fence **foreign** IPs (4pda, habr, kinopoisk, gosuslugi, banking…) | **DIRECT** | 37 |
| `our-ads`          | Ad / tracking networks | **BLOCK** | 89 |
| `our-winspy`       | Windows telemetry | **BLOCK** | 381 |
| `our-torrent`      | Torrent trackers / DHT | **BLOCK** | 838 |

> Counts are real, taken after harvest+dedup. Re-run `build_sources.sh` to refresh.

## Sources

- **roscomvpn** (plaintext `data/`): `https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/<name>`
  — `whitelist`, `category-ru`, `category-geoblock-ru`, `torrent`, `win-spy`, `category-ads`.
- **Loyalsoldier/v2ray-rules-dat** (`release` branch): `win-spy.txt` (telemetry enrichment).
- **v2fly/domain-list-community** (`master/data`): `category-public-tracker` (torrent enrichment),
  `category-ads-all` + ad-network leaf lists (`openx`, `pubmatic`, `taboola`, `segment`, `adjust`,
  `ogury`, `supersonic`, `growingio`, `clearbit`) for ads enrichment.
- **Curated by us** (in `build_sources.sh`): banks, NSPK/MirPay, gov, marketplaces, telecom,
  media, VK/Mail/Yandex clusters, IDN `.рф`, and the main global ad/tracking networks.

All lists are public and harvesting plaintext is legal.

> We deliberately did **not** use Loyalsoldier `reject-list.txt` (167k lines) for `our-ads` —
> it is a DNS-style blocklist that would bloat `geosite.dat` and hurt routing match speed.
> `our-ads` is a lean, routing-appropriate curated set instead.

## Cherry-pick heuristic for `our-geoblock-ru` (CRITICAL)

roscomvpn's `category-geoblock-ru` is **mixed**: it contains both RU services that
block foreign IPs **and** foreign services that block RU IPs. These need *opposite*
routing:

- **RU services that geo-fence foreign IPs** → need a **RU IP** → `our-geoblock-ru` → **DIRECT**.
- **Foreign services that geo-fence RU IPs** (Adobe, OpenAI, Spotify, Behance(=Adobe),
  arkoselabs, crashlytics, ftcdn, Netflix, Claude, DeepL, JetBrains, Notion, Reddit, TikTok…)
  → need a **FOREIGN exit** → must **NOT** be `direct` → we **exclude** them so they fall
  through to default (proxy).

The split heuristic:

1. **Primary = section position.** The upstream file has an explicit marker
   `# Зарубежные сайты...`. Everything **before** it (the RU block) is kept;
   everything **after** it (foreign brands, grouped by `# <Brand>` headers) is dropped.
2. **Secondary safety net.** Re-scan the foreign block and *rescue* any `*.ru` / `*.su` /
   `.рф` (`xn--p1ai`) domains that might be misfiled there — **minus a deny-list** of
   foreign services that merely use a RU-looking TLD but are **not** Russian
   (`happ.su` = proxy client, `kemono.su` = foreign aggregator). **TLD alone is not trusted.**
3. **Plus our curated RU services** (banks/NSPK/gov/marketplaces/media).

**Result of the split on the real data:**
- Kept (RU side, → DIRECT), examples: `4pda.ru`, `4pda.to`, `habr.com`, `habrastorage.org`,
  `onlinesim.io` (RU SMS-activation, geo-fences), plus curated `sberbank.ru`, `alfabank.ru`,
  `vtb.ru`, `gosuslugi.ru`, `nalog.ru`, `cbr.ru`, `mos.ru`, `ozon.ru`, `wildberries.ru`,
  `kinopoisk.ru`.
- Dropped (foreign side, → default/proxy), examples of the ~80 brand sections excluded:
  `# Adobe`, `# OpenAI / ChatGPT`, `# Claude`, `# Spotify`, `# Netflix`, `# DeepL`,
  `# Jetbrains`, `# Notion`, `# Reddit`, `# Tiktok / CapCut / ByteDance`, `# Grok`,
  `# Meta AI`, `# Google DeepMind (Gemini)` … (`arkoselabs` / `crashlytics` / `ftcdn` live in
  the `# Остальное` tail and are likewise excluded).
- A CI safety gate fails the build if any of `adobe|openai|spotify|behance|arkoselabs|crashlytics|ftcdn|netflix|claude`
  ever appears in `our-geoblock-ru`.

## Build

Requires Go (compiler) + bash/curl/awk (sources).

```bash
# 1. (re)generate plaintext category sources in data/ from upstream
./build_sources.sh

# 2. build the v2fly compiler and compile geosite.dat
git clone --depth 1 https://github.com/v2fly/domain-list-community.git /tmp/dlc
( cd /tmp/dlc && GOFLAGS=-mod=mod go build -o /tmp/dlc-compiler . )
/tmp/dlc-compiler -datapath ./data -outputdir ./ -outputname geosite.dat
sha256sum geosite.dat | tee geosite.dat.sha256sum

# 3. (optional) verify a category resolves out of the compiled .dat
/tmp/dlc-compiler -datapath ./data -outputdir /tmp/verify -outputname geosite.dat \
  -exportlists "our-whitelist,our-geoblock-ru"
```

`geosite.dat` in this repo is **already compiled** (Go 1.25.6, darwin/arm64) and is reproducible
— same `data/` yields the same sha256.

## CI (GitHub Actions)

`.github/workflows/build.yml` compiles `geosite.dat` on push to `main` (when `data/**`
changes), daily on a schedule, and on manual dispatch. It then publishes a **GitHub
Release tagged with a UTC timestamp** `YYYYMMDDHHmm` (same convention as roscomvpn /
Loyalsoldier), attaching `geosite.dat` + `geosite.dat.sha256sum`. Manual dispatch with
`refresh_sources=true` re-harvests upstream and commits the `data/` diff first.

## Hosting

1. **Primary (our own URL):** serve the release asset from our infra, e.g.
   `https://geo.example.com/geosite-<tag>.dat`. Pin clients to a tag, not `latest`.
2. **Mirror via jsDelivr (pinned to a release tag):**
   `https://cdn.jsdelivr.net/gh/<org>/<repo>@<tag>/geosite.dat`
   — pin the tag (`@20260622...`), **never** `@latest`/`@master`, so a compromised push
   can't silently change routing.

> Under whitelist-only ТСПУ, jsDelivr may be unreachable — the **primary self-hosted URL behind
> our RU-CDN front** is the load-bearing path; the architecture also ships a **bootstrap geosite
> inline in the subscription** (see `vpn-ideal-architecture.md` §L0/L5). jsDelivr is a convenience
> mirror only.

## How xray references the categories — `geosite:` vs `ext:`

Two ways to point xray's routing rules at our lists:

- **`geosite:our-whitelist`** — requires our `geosite.dat` to be the node's **primary**
  `geosite.dat` asset (placed at `XRAY_LOCATION_ASSET`, replacing the built-in). Clean syntax,
  but it **overwrites the bundled geosite.dat**, so you lose upstream built-ins
  (`geosite:google`, `geosite:netflix`, …) unless you merge them in.
- **`ext:our-geosite.dat:our-whitelist`** — loads our file as a **separate** asset
  (`our-geosite.dat`) alongside the stock `geosite.dat`, **without clobbering** the built-ins.

### Recommendation: use `ext:`

Ship our file **as a separate asset** `our-geosite.dat` and reference it with
**`ext:our-geosite.dat:<category>`**. Rationale:

- Keeps the stock `geosite.dat` intact, so default-proxy rules can still use upstream
  categories (`geosite:netflix`, `geosite:openai`, …) — exactly what the foreign
  geo-blockers we excluded from `our-geoblock-ru` should match for proxying.
- Decouples our release cadence (timestamp tags) from the bundled geosite shipped with the
  xray binary — we update `our-geosite.dat` without touching the base asset.
- Avoids a class of "our build forgot category X that a default rule relied on" outages.

Example routing rules (happ/xray):

```jsonc
"rules": [
  { "type": "field", "outboundTag": "block",
    "domain": ["ext:our-geosite.dat:our-ads",
               "ext:our-geosite.dat:our-winspy",
               "ext:our-geosite.dat:our-torrent"] },

  { "type": "field", "outboundTag": "direct",
    "ip": ["geoip:private", "geoip:ru"] },
  { "type": "field", "outboundTag": "direct",
    "domain": ["ext:our-geosite.dat:our-whitelist",
               "ext:our-geosite.dat:our-category-ru",
               "ext:our-geosite.dat:our-geoblock-ru"] }

  // everything else (incl. adobe/openai/spotify/... excluded from our-geoblock-ru)
  // falls through to the default balancer/proxy outbound.
]
```

Deploy: place `our-geosite.dat` next to the node's `geosite.dat` in
`XRAY_LOCATION_ASSET` (default `/usr/local/share/xray/`). If you instead make ours the
**only** asset, rename it to `geosite.dat` and switch the rules to the `geosite:<name>` form.
