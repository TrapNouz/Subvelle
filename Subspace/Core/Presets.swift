import Foundation
public struct ServicePreset: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let category: Category
    public var symbol: String { category.symbol }
    public var initials: String { String(name.split(separator: " ").prefix(2).compactMap(\.first)) }
    public static let all: [Self] = {
        let groups: [(Category, [String])] = [
            (.streaming, ["Netflix", "Disney+", "YouTube Premium", "Apple TV", "Prime Video", "Hulu", "HBO Max", "Peacock", "Paramount+", "Crunchyroll", "MUBI", "BritBox", "Shudder", "Discovery+", "Criterion Channel", "Fubo", "DAZN", "YouTube TV", "Crave", "CBC Gem", "ICI TOU.TV EXTRA", "Club illico", "Nebula", "Plex Pass", "ESPN+", "Sling TV", "NBA League Pass", "Apple One"]),
            (.music, ["Spotify", "Apple Music", "Tidal", "YouTube Music", "Deezer", "Amazon Music", "SoundCloud Go", "Qobuz", "Pandora"]),
            (.ai, ["ChatGPT", "Claude", "Gemini", "Perplexity", "Cursor", "Midjourney", "GitHub Copilot", "Runway", "ElevenLabs", "Poe", "Le Chat Pro", "DeepL Pro", "SuperGrok", "Character.AI"]),
            (.gaming, ["Xbox Game Pass", "PlayStation Plus", "Nintendo Switch Online", "Roblox Premium", "EA Play", "Ubisoft+", "GeForce NOW", "Apple Arcade", "Humble Choice", "Final Fantasy XIV", "World of Warcraft", "Twitch Turbo", "Discord Nitro", "Google Play Pass"]),
            (.privacy, ["Mullvad", "Proton", "NordVPN", "Surfshark", "1Password", "Bitwarden", "addy.io", "ExpressVPN", "IVPN", "SimpleLogin", "Dashlane", "Proton VPN", "Kagi"]),
            (.productivity, ["Microsoft 365", "Notion", "Adobe Creative Cloud", "Todoist", "Evernote", "Slack", "Zoom", "Canva", "Fantastical", "Things Cloud", "Grammarly", "Obsidian Sync", "Readwise", "Superhuman", "Medium", "Feedly Pro"]),
            (.cloud, ["iCloud+", "Google One", "Dropbox", "Box", "OneDrive", "Backblaze", "pCloud", "MEGA", "Sync.com"]),
            (.fitness, ["Apple Fitness+", "Strava", "Peloton", "Fitbod", "Headspace", "Calm", "MyFitnessPal", "Whoop", "Oura", "Nike Training", "ClassPass", "AllTrails+", "Fitbit Premium", "Garmin Connect+", "Zwift"]),
            (.education, ["Duolingo", "Coursera", "Skillshare", "MasterClass", "Brilliant", "LinkedIn Learning", "Codecademy", "Babbel", "DataCamp", "Blinkist", "Udemy Personal Plan", "Kobo Plus"]),
            (.news, ["The New York Times", "The Washington Post", "The Economist", "The Guardian", "Financial Times", "The Wall Street Journal", "The Atlantic", "The New Yorker", "Apple News+", "The Globe and Mail"]),
            (.hosting, ["Squarespace", "Wix", "Webflow", "WordPress.com", "Ghost", "Shopify", "DigitalOcean", "Linode", "Hetzner", "Cloudflare", "Vercel", "Netlify"]),
            (.developer, ["GitHub", "GitLab", "JetBrains", "Tower", "Postman", "Sentry", "Linear", "Figma", "Sketch", "Docker", "Expo", "Raycast", "Setapp", "Tailscale"]),
            (.other, ["Audible", "Kindle Unlimited", "Patreon", "Substack", "Amazon Prime", "Costco", "Instacart+", "Uber One", "DoorDash DashPass", "NYT Games", "X Premium", "Snapchat+", "Telegram Premium", "Reddit Premium", "Tinder", "Bumble", "Hinge", "Lyft Pink", "Skip+", "Fizz", "Vidéotron", "Bell", "Rogers", "Telus", "Koodo", "Fido"])
        ]
        return groups.flatMap { category, names in names.map { Self(name: $0, category: category) } }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()
}
