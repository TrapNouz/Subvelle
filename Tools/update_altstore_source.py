"""Maintains altstore/source.json, an AltStore-format source that Feather, AltStore and SideStore can add.

  python3 Tools/update_altstore_source.py bootstrap              # rebuild from GitHub releases (needs gh)
  python3 Tools/update_altstore_source.py add --version 1.3.0 --build 26 \
      --url https://github.com/OWNER/REPO/releases/download/v1.3.0/Subvelle-1.3.0-26.ipa \
      --size 1407678 [--date 2026-11-27T10:00:00Z] [--notes "What's new"]

`add` replaces an existing entry for the same version, keeps versions newest first, and mirrors the
newest one into the legacy top-level fields that older source readers use.
"""
import argparse, datetime, json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(REPO, "altstore/source.json")
GITHUB = "TrapNouz/Subvelle"
RAW = f"https://raw.githubusercontent.com/{GITHUB}/main"
BUNDLE_ID = "app.subspace.ios"
DEFAULT_NOTES = "Bug fixes and improvements. Full notes: https://github.com/" + GITHUB + "/releases"

def skeleton():
    return {
        "name": "Subvelle",
        "identifier": "app.subvelle.source",
        "subtitle": "Private subscription tracker",
        "description": "The official source for Subvelle: a private, local-first subscription tracker. "
                       "Add this source to get new versions as soon as they are published on GitHub.",
        "iconURL": f"{RAW}/Subspace/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "headerURL": f"{RAW}/docs/subvelle-logo.png",
        "website": f"https://github.com/{GITHUB}",
        "tintColor": "#B099FF",
        "featuredApps": [BUNDLE_ID],
        "apps": [{
            "name": "Subvelle",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "TrapNouz",
            "subtitle": "Know what you pay, what renews next.",
            "localizedDescription": (
                "Subvelle tracks your subscriptions privately, on your iPhone. No account, ads, tracking or bank access.\n\n"
                "• Folder home screen: Overview, Subscriptions, Analytics and Settings pop out over a blurred background\n"
                "• 192 services with their logos, or add your own\n"
                "• Normalized monthly, yearly and weekly costs in any currency\n"
                "• Charts, a payment calendar and renewal reminders\n"
                "• JSON backups, automatic iCloud Drive backup, and import from Files\n"
                "• Check for updates in Settings"),
            "iconURL": f"{RAW}/Subspace/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
            "tintColor": "#B099FF",
            "category": "utilities",
            "screenshots": [],
            "appPermissions": {"entitlements": [], "privacy": {}},
            "versions": [],
        }],
        "news": [],
    }

def version_key(v):
    return tuple(int(p) for p in re.findall(r"\d+", v["version"])[:3])

def add_version(source, version, build, url, size, date, notes):
    app = source["apps"][0]
    entry = {"version": version, "buildVersion": str(build), "date": date, "localizedDescription": notes or DEFAULT_NOTES,
             "downloadURL": url, "size": int(size), "minOSVersion": "26.0"}
    app["versions"] = sorted([v for v in app["versions"] if v["version"] != version] + [entry], key=version_key, reverse=True)
    latest = app["versions"][0]
    # Legacy fields (AltStore source v1) for readers that only look at the newest version.
    app.update({"version": latest["version"], "versionDate": latest["date"], "versionDescription": latest["localizedDescription"],
                "downloadURL": latest["downloadURL"], "size": latest["size"]})
    return source

def load():
    return json.load(open(SOURCE)) if os.path.exists(SOURCE) else skeleton()

def save(source):
    os.makedirs(os.path.dirname(SOURCE), exist_ok=True)
    with open(SOURCE, "w") as f:
        json.dump(source, f, indent=2, ensure_ascii=False); f.write("\n")

def bootstrap():
    out = subprocess.run(["gh", "api", f"repos/{GITHUB}/releases", "--paginate"], capture_output=True, text=True, check=True).stdout
    source = skeleton()
    for release in json.loads(out):
        if release.get("draft"): continue
        for asset in release.get("assets", []):
            match = re.fullmatch(r"(?:Subvelle|Subspace)-(\d+\.\d+\.\d+)-(\d+)\.ipa", asset["name"])
            if match:
                add_version(source, match.group(1), match.group(2), asset["browser_download_url"], asset["size"], release["published_at"], None)
    return source

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("bootstrap")
    add = sub.add_parser("add")
    for name in ("version", "build", "url", "size"): add.add_argument(f"--{name}", required=True)
    add.add_argument("--date", default=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    add.add_argument("--notes", default=None)
    args = parser.parse_args()
    if args.command == "bootstrap":
        save(bootstrap())
    else:
        if not re.fullmatch(r"\d+\.\d+\.\d+", args.version): sys.exit("version must be MAJOR.MINOR.PATCH")
        save(add_version(load(), args.version, args.build, args.url, args.size, args.date, args.notes))
    source = load()
    print(f"{SOURCE}: {len(source['apps'][0]['versions'])} versions, latest {source['apps'][0].get('version')}")
