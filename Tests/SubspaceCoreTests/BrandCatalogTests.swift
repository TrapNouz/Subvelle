import Testing
@testable import SubspaceCore

@Suite("Service presets and brand icons") struct BrandCatalogTests {
    @Test("Every preset has a logo or a brand colour, and names are unique")
    func everyPresetHasABrand() {
        let names = ServicePreset.all.map(\.name)
        #expect(names.count == 192)
        #expect(Set(names).count == names.count)
        let missing = names.filter { BrandCatalog.brand(for: $0) == nil }
        #expect(missing.isEmpty, "No brand for: \(missing)")
        #expect(ServicePreset.all.filter { BrandCatalog.brand(for: $0.name)?.logo != nil }.count >= 120)
    }

    @Test("Names match exactly, by brand, by prefix, and without accents")
    func matching() {
        #expect(BrandCatalog.brand(for: "Netflix")?.logo == "brand-netflix")
        #expect(BrandCatalog.brand(for: "Claude")?.logo == "brand-claude")
        #expect(BrandCatalog.brand(for: "claude pro")?.logo == "brand-claude")
        #expect(BrandCatalog.brand(for: "Spotify Family")?.logo == "brand-spotify")
        #expect(BrandCatalog.brand(for: "YouTube")?.logo == "brand-youtube")
        #expect(BrandCatalog.brand(for: "Disney Plus")?.hex == "113CCF")
        #expect(BrandCatalog.brand(for: "Videotron") == BrandCatalog.brand(for: "Vidéotron"))
        #expect(BrandCatalog.brand(for: "Plan 01") == nil)
        #expect(BrandCatalog.brand(for: "My subscription") == nil)
        #expect(BrandCatalog.brand(for: "") == nil)
    }

    @Test("Foreground contrast follows the brand colour")
    func contrast() {
        #expect(Brand(logo: nil, hex: "FFFC00").prefersDarkForeground)   // Snapchat yellow
        #expect(!Brand(logo: nil, hex: "E50914").prefersDarkForeground)  // Netflix red
        #expect(!Brand(logo: nil, hex: "000000").prefersDarkForeground)
    }
}
