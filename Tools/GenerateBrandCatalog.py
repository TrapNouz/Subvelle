"""Builds Presets.swift, BrandCatalog.swift and the brand logo asset catalog from Simple Icons (CC0)."""
import json, os, re, shutil, sys

PKG = sys.argv[1]           # extracted simple-icons package dir
REPO = sys.argv[2]          # app repository root
icons = {i['slug']: i for i in json.load(open(os.path.join(PKG, 'data/simple-icons.json')))}
by_title = {i['title'].lower(): i for i in icons.values()}

# Category -> services. Original 147 plus additions (marked by being new names).
GROUPS = {
 'streaming': ["Netflix", "Disney+", "YouTube Premium", "Apple TV", "Prime Video", "Hulu", "HBO Max", "Peacock", "Paramount+", "Crunchyroll", "MUBI", "BritBox", "Shudder", "Discovery+", "Criterion Channel", "Fubo", "DAZN",
               "YouTube TV", "Crave", "CBC Gem", "ICI TOU.TV EXTRA", "Club illico", "Nebula", "Plex Pass", "ESPN+", "Sling TV", "NBA League Pass", "Apple One"],
 'music': ["Spotify", "Apple Music", "Tidal", "YouTube Music", "Deezer", "Amazon Music", "SoundCloud Go", "Qobuz", "Pandora"],
 'ai': ["ChatGPT", "Claude", "Gemini", "Perplexity", "Cursor", "Midjourney", "GitHub Copilot", "Runway", "ElevenLabs", "Poe",
        "Le Chat Pro", "DeepL Pro", "SuperGrok", "Character.AI"],
 'gaming': ["Xbox Game Pass", "PlayStation Plus", "Nintendo Switch Online", "Roblox Premium", "EA Play", "Ubisoft+", "GeForce NOW", "Apple Arcade", "Humble Choice", "Final Fantasy XIV", "World of Warcraft",
            "Twitch Turbo", "Discord Nitro", "Google Play Pass"],
 'privacy': ["Mullvad", "Proton", "NordVPN", "Surfshark", "1Password", "Bitwarden", "addy.io", "ExpressVPN", "IVPN", "SimpleLogin", "Dashlane",
             "Proton VPN", "Kagi"],
 'productivity': ["Microsoft 365", "Notion", "Adobe Creative Cloud", "Todoist", "Evernote", "Slack", "Zoom", "Canva", "Fantastical", "Things Cloud", "Grammarly", "Obsidian Sync", "Readwise", "Superhuman",
                  "Medium", "Feedly Pro"],
 'cloud': ["iCloud+", "Google One", "Dropbox", "Box", "OneDrive", "Backblaze", "pCloud", "MEGA", "Sync.com"],
 'fitness': ["Apple Fitness+", "Strava", "Peloton", "Fitbod", "Headspace", "Calm", "MyFitnessPal", "Whoop", "Oura", "Nike Training", "ClassPass",
             "AllTrails+", "Fitbit Premium", "Garmin Connect+", "Zwift"],
 'education': ["Duolingo", "Coursera", "Skillshare", "MasterClass", "Brilliant", "LinkedIn Learning", "Codecademy", "Babbel", "DataCamp", "Blinkist",
               "Udemy Personal Plan", "Kobo Plus"],
 'news': ["The New York Times", "The Washington Post", "The Economist", "The Guardian", "Financial Times", "The Wall Street Journal", "The Atlantic", "The New Yorker", "Apple News+", "The Globe and Mail"],
 'hosting': ["Squarespace", "Wix", "Webflow", "WordPress.com", "Ghost", "Shopify", "DigitalOcean", "Linode", "Hetzner", "Cloudflare", "Vercel", "Netlify"],
 'developer': ["GitHub", "GitLab", "JetBrains", "Tower", "Postman", "Sentry", "Linear", "Figma", "Sketch", "Docker", "Expo", "Raycast", "Setapp",
               "Tailscale"],
 'other': ["Audible", "Kindle Unlimited", "Patreon", "Substack", "Amazon Prime", "Costco", "Instacart+", "Uber One", "DoorDash DashPass", "NYT Games",
           "X Premium", "Snapchat+", "Telegram Premium", "Reddit Premium", "Tinder", "Bumble", "Hinge", "Lyft Pink", "Skip+",
           "Fizz", "Vidéotron", "Bell", "Rogers", "Telus", "Koodo", "Fido"],
}

# Service -> Simple Icons slug, where the service is shown with its parent brand's logo.
SLUG = {
 "YouTube Premium": "youtube", "SoundCloud Go": "soundcloud", "Gemini": "googlegemini", "PlayStation Plus": "playstation",
 "Roblox Premium": "roblox", "Ubisoft+": "ubisoft", "GeForce NOW": "nvidia", "Humble Choice": "humblebundle",
 "Things Cloud": "things", "Obsidian Sync": "obsidian", "iCloud+": "icloud", "Google One": "google",
 "Apple Fitness+": "apple", "Nike Training": "nike", "The New York Times": "newyorktimes", "Apple News+": "applenews",
 "WordPress.com": "wordpress", "Instacart+": "instacart", "Uber One": "uber", "DoorDash DashPass": "doordash",
 "NYT Games": "newyorktimes", "YouTube TV": "youtubetv", "CBC Gem": "cbc", "Plex Pass": "plex", "NBA League Pass": "nba",
 "Apple One": "apple", "Le Chat Pro": "mistralai", "DeepL Pro": "deepl", "Twitch Turbo": "twitch", "Discord Nitro": "discord",
 "Google Play Pass": "googleplay", "Proton VPN": "protonvpn", "Feedly Pro": "feedly", "AllTrails+": "alltrails",
 "Fitbit Premium": "fitbit", "Garmin Connect+": "garmin", "Udemy Personal Plan": "udemy", "Kobo Plus": "rakutenkobo",
 "X Premium": "x", "Snapchat+": "snapchat", "Telegram Premium": "telegram", "Reddit Premium": "reddit", "Lyft Pink": "lyft",
 "HBO Max": "hbomax", "Paramount+": "paramountplus",
}
# Brand colours for services without an available logo (the brand asked Simple Icons to remove it,
# or it was never included). Shown as a monogram tile. Approximate official colours.
COLOR = {
 "Disney+": "113CCF", "Prime Video": "00A8E1", "Hulu": "1CE783", "Peacock": "000000", "BritBox": "1B1F5E", "Shudder": "D71920",
 "Discovery+": "2175D9", "Criterion Channel": "000000", "Crave": "0F1A4A", "ICI TOU.TV EXTRA": "E4003B", "Club illico": "FF6B00",
 "ESPN+": "CC0000", "Sling TV": "0057FF", "Amazon Music": "25D1DA", "Qobuz": "000000", "ChatGPT": "10A37F", "Midjourney": "000000",
 "Runway": "000000", "SuperGrok": "000000", "Character.AI": "000000", "Xbox Game Pass": "107C10", "Nintendo Switch Online": "E60012",
 "EA Play": "FF4747", "Final Fantasy XIV": "1C3F94", "World of Warcraft": "148EFF", "IVPN": "2F3C4B", "Microsoft 365": "D83B01",
 "Adobe Creative Cloud": "DA1F26", "Slack": "4A154B", "Canva": "00C4CC", "Fantastical": "E2403C", "Readwise": "1F1F1F",
 "Superhuman": "6E44FF", "OneDrive": "0078D4", "pCloud": "17BED0", "Sync.com": "1E88E5", "Fitbod": "2B2B2B", "Calm": "3B7BE0",
 "MyFitnessPal": "0066EE", "Whoop": "000000", "Oura": "000000", "ClassPass": "0055FF", "Zwift": "FC6719", "MasterClass": "000000",
 "Brilliant": "000000", "LinkedIn Learning": "0A66C2", "Babbel": "F45B26", "Blinkist": "2CE080", "The Economist": "E3120B",
 "Financial Times": "FCD0B1", "The Wall Street Journal": "000000", "The Atlantic": "000000", "The New Yorker": "000000",
 "The Globe and Mail": "000000", "Linode": "00A95C", "Kindle Unlimited": "146EB4", "Amazon Prime": "00A8E1", "Costco": "E31837",
 "Bumble": "FFC629", "Hinge": "000000", "Skip+": "FF8000", "Vidéotron": "FFD100", "Bell": "00549A", "Rogers": "DA291C",
 "Telus": "4B286D", "Koodo": "0098A6", "Fido": "FFD100",
}

def norm(name):
    import unicodedata
    folded = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]', '', folded.lower().replace('+', 'plus'))

entries = {}   # normalized name -> (slug or None, hex)
missing_color = []
for services in GROUPS.values():
    for service in services:
        slug = SLUG.get(service) or (by_title[service.lower()]['slug'] if service.lower() in by_title else None)
        if slug is not None and slug not in icons: sys.exit(f"unknown slug {slug} for {service}")
        hexcolor = icons[slug]['hex'] if slug else COLOR.get(service)
        if hexcolor is None: missing_color.append(service)
        entries[norm(service)] = (slug, hexcolor)
        if slug:  # also recognise the plain brand name, e.g. "YouTube" or "Claude"
            entries.setdefault(norm(icons[slug]['title']), (slug, hexcolor))
if missing_color: sys.exit(f"no logo or colour for: {missing_color}")

# ---- Presets.swift
CASE = {'streaming': 'streaming', 'music': 'music', 'ai': 'ai', 'gaming': 'gaming', 'privacy': 'privacy', 'productivity': 'productivity',
        'cloud': 'cloud', 'fitness': 'fitness', 'education': 'education', 'news': 'news', 'hosting': 'hosting', 'developer': 'developer', 'other': 'other'}
total = sum(len(v) for v in GROUPS.values())
lines = ",\n".join(f"            (.{CASE[k]}, [{', '.join(json.dumps(s, ensure_ascii=False) for s in v)}])" for k, v in GROUPS.items())
presets = open(os.path.join(REPO, 'Subspace/Core/Presets.swift')).read()
start = presets.index('        let groups: [(Category, [String])] = [')
end = presets.index('        ]\n', start)
presets = presets[:start] + f"        let groups: [(Category, [String])] = [\n{lines}\n" + presets[end:]
open(os.path.join(REPO, 'Subspace/Core/Presets.swift'), 'w').write(presets)

# ---- BrandCatalog.swift
rows = "\n".join(f'        "{k}": Brand(logo: {json.dumps("brand-" + s) if s else "nil"}, hex: "{h}"),' for k, (s, h) in sorted(entries.items()))
open(os.path.join(REPO, 'Subspace/Core/BrandCatalog.swift'), 'w').write(f'''import Foundation

/// Logo and colour for known services, matched by name. Logos are vector assets from Simple Icons
/// (CC0, https://simpleicons.org); brand names and logos are trademarks of their owners and are shown
/// only to identify a subscription. Brands without an available logo get a monogram in their colour.
/// Generated from the Simple Icons data; regenerate rather than editing by hand.
public struct Brand: Equatable, Sendable {{
    /// Asset name of the logo, or nil for a monogram.
    public let logo: String?
    /// Brand colour as RRGGBB.
    public let hex: String
    /// Relative luminance of the brand colour (0 = black, 1 = white).
    public var luminance: Double {{
        guard let value = UInt32(hex, radix: 16) else {{ return 0 }}
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        func linear(_ c: Double) -> Double {{ c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }}
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }}
    /// Whether a dark logo/monogram reads better than white on the brand colour.
    public var prefersDarkForeground: Bool {{ luminance > 0.45 }}
}}

public enum BrandCatalog {{
    /// Lowercased, accent-free name with everything but letters and digits removed ("+" becomes "plus").
    public static func key(_ name: String) -> String {{
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        return String(folded.replacingOccurrences(of: "+", with: "plus").unicodeScalars.filter {{ $0.isASCII && CharacterSet.alphanumerics.contains($0) }}.map(Character.init))
    }}
    /// The brand for a service name: an exact match, else the longest run of whole leading words that
    /// names a brand ("Claude Pro" and "Spotify Family" find their logos; "Applebee's" is not Apple).
    public static func brand(for name: String) -> Brand? {{
        let words = name.components(separatedBy: .whitespaces).map(key).filter {{ !$0.isEmpty }}
        guard !words.isEmpty else {{ return nil }}
        for length in stride(from: words.count, through: 1, by: -1) {{
            if let brand = entries[words.prefix(length).joined()] {{ return brand }}
        }}
        return nil
    }}
    static let entries: [String: Brand] = [
{rows}
    ]
}}
''')

# ---- Asset catalog: one template-rendered vector image set per logo
brands_dir = os.path.join(REPO, 'Subspace/Resources/Assets.xcassets/Brands')
shutil.rmtree(brands_dir, ignore_errors=True)
os.makedirs(brands_dir)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(brands_dir, 'Contents.json'), 'w'), indent=2)
used = sorted({s for s, _ in entries.values() if s})
for slug in used:
    d = os.path.join(brands_dir, f'brand-{slug}.imageset'); os.makedirs(d)
    shutil.copy(os.path.join(PKG, 'icons', f'{slug}.svg'), os.path.join(d, f'{slug}.svg'))
    json.dump({"images": [{"filename": f"{slug}.svg", "idiom": "universal"}], "info": {"author": "xcode", "version": 1},
               "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"}},
              open(os.path.join(d, 'Contents.json'), 'w'), indent=2)
with_logo = sum(1 for g in GROUPS.values() for s in g if entries[norm(s)][0])
print(f"presets={total} with_logo={with_logo} monogram={total - with_logo} logo_assets={len(used)} catalog_keys={len(entries)}")

# ---- Android: the same presets, brand catalog and logos (vector drawables)
ANDROID = os.path.join(REPO, 'android/app/src/main')
if os.path.isdir(ANDROID):
    KCASE = {k: k.upper() for k in GROUPS}
    klines = ",\n".join(f"                Category.{KCASE[k]} to listOf({', '.join(json.dumps(s, ensure_ascii=False) for s in v)})" for k, v in GROUPS.items())
    catalog_kt = os.path.join(ANDROID, 'java/app/subspace/core/Catalog.kt')
    src = open(catalog_kt).read()
    a = src.index('            val groups = listOf(\n') + len('            val groups = listOf(\n')
    b = src.index('\n            )\n', a)
    src = src[:a] + klines + src[b:]
    src = re.sub(r'/\*\* Same \d+ services as the iOS app\.', f'/** Same {total} services as the iOS app.', src)
    open(catalog_kt, 'w').write(src)

    drawable = os.path.join(ANDROID, 'res/drawable')
    for old in os.listdir(drawable):
        if old.startswith('brand_'): os.remove(os.path.join(drawable, old))
    for slug in used:
        svg = open(os.path.join(PKG, 'icons', f'{slug}.svg')).read()
        paths = re.findall(r'<path d="([^"]+)"', svg)
        if not paths: sys.exit(f"no path in {slug}")
        body = "\n".join(f'    <path android:fillColor="#FFFFFFFF" android:pathData="{p}" />' for p in paths)
        open(os.path.join(drawable, f'brand_{slug}.xml'), 'w').write(
            f'<?xml version="1.0" encoding="utf-8"?>\n<!-- {icons[slug]["title"]} logo from Simple Icons (CC0). Trademark of its owner. -->\n'
            f'<vector xmlns:android="http://schemas.android.com/apk/res/android"\n    android:width="24dp" android:height="24dp"\n'
            f'    android:viewportWidth="24" android:viewportHeight="24">\n{body}\n</vector>\n')

    krows = "\n".join(f'        "{k}" to Brand({("R.drawable.brand_" + s) if s else "null"}, 0xFF{h}),' for k, (s, h) in sorted(entries.items()))
    open(os.path.join(ANDROID, 'java/app/subspace/ui/BrandCatalog.kt'), 'w').write(f'''package app.subspace.ui

import androidx.annotation.DrawableRes
import androidx.compose.runtime.Immutable
import app.subspace.R
import java.text.Normalizer

/**
 * Logo and colour for known services, matched by name. Logos are vector drawables from Simple Icons
 * (CC0, https://simpleicons.org); brand names and logos are trademarks of their owners and are shown
 * only to identify a subscription. Brands without an available logo get a monogram in their colour.
 * Generated by Tools/GenerateBrandCatalog.py, the same data as the iPhone app; regenerate, don't edit.
 */
@Immutable
data class Brand(@DrawableRes val logo: Int?, val argb: Long) {{
    private fun linear(c: Double) = if (c <= 0.04045) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)
    val luminance: Double get() {{
        val r = ((argb shr 16) and 0xFF) / 255.0; val g = ((argb shr 8) and 0xFF) / 255.0; val b = (argb and 0xFF) / 255.0
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }}
    val prefersDarkForeground: Boolean get() = luminance > 0.45
}}

object BrandCatalog {{
    /** Lowercased, accent-free name with everything but letters and digits removed ("+" becomes "plus"). */
    fun key(name: String): String =
        Normalizer.normalize(name, Normalizer.Form.NFKD).lowercase().replace("+", "plus").filter {{ it in 'a'..'z' || it in '0'..'9' }}

    /**
     * Exact match, else the longest run of whole leading words that names a brand
     * ("Claude Pro" and "Spotify Family" find their logos; "Applebee's" is not Apple).
     */
    fun brand(name: String): Brand? {{
        val words = name.split(' ', '\\t', '\\n').map(::key).filter {{ it.isNotEmpty() }}
        for (length in words.size downTo 1) {{
            entries[words.take(length).joinToString("")]?.let {{ return it }}
        }}
        return null
    }}

    private val entries: Map<String, Brand> = mapOf(
{krows}
    )
}}
''')
    print(f"android: presets={total} drawables={len(used)}")
