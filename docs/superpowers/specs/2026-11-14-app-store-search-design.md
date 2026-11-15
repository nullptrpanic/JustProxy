# App Store Search Metadata Design

Status: Version 1.0.2 (build 9) was submitted on November 14, 2026 at 22:54 China Standard Time and confirmed `READY_FOR_SALE` on November 15. Both localizations were saved and read back successfully. The build is available to the existing JustProxy internal TestFlight group. The public US Search API returns the app, but the user's native App Store exact-name search remains unresolved. This document records the original metadata-only release; the subsequent bilingual implementation is described in `2026-11-15-bilingual-localization-design.md`.

## Intent

Make JustProxy easier to discover through relevant Chinese and English searches while keeping its public name exactly `JustProxy`. The primary user outcome is that searching for `justproxy` in the US App Store returns this app (Apple ID `6833256224`). This is a metadata change; it does not add app features or localize the app binary. Saving metadata or submitting a release does not establish that the search outcome has been achieved.

## Scope and constraints

- Keep the name `JustProxy` in every locale and preserve the bundle identifier.
- Improve the existing `zh-Hans` subtitle, keywords, and description.
- Add an `en-US` subtitle, keywords, and description.
- Keep the primary locale, pricing, distribution territories, support URL, and privacy URL unchanged.
- Describe only the current HTTP proxy, HTTPS CONNECT, reachable-network access, and session traffic features.
- Disclose that the interface and built-in guide remain in Simplified Chinese in the English description.
- Do not imply VPN service, HTTPS decryption, automatic forwarding of all device traffic, guaranteed background execution, or guaranteed search rankings.
- Public US storefront availability and invalid-link behavior remain a separate unresolved issue. Submitting this metadata is not evidence that either issue is fixed.

## Approaches

1. Add a functional suffix to the public name. This would put HTTP proxy terminology in the title, but would change the public name. It is excluded by the user's final instruction.
2. Keep the name and use localized subtitles and keywords for functional terms. This is the selected direction because it preserves the brand while improving the specificity and language coverage of searchable metadata.

## Proposed fields

| Field | Simplified Chinese | English (United States) |
| --- | --- | --- |
| Name | JustProxy | JustProxy |
| Subtitle | HTTP代理与实时流量统计 | HTTP Proxy & Traffic Monitor |

Keyword strings, complete descriptions, and release notes are maintained in:

- `AppStore/metadata/zh-Hans.json`
- `AppStore/metadata/en-US.json`

These files are release inputs, not complete API requests. Each contains app-level information separately from version-level information. Resolve the editable app information and version identifiers before applying any future API request; do not reuse identifiers for an already released version. Actual API responses and publication state belong in the ignored release artifact directory.

Place the main functional terms in the subtitle. Use the keyword field for related protocols, networking contexts, connection records, and upload/download concepts. Avoid repeating the app name, subtitle terms, category terms, competitor names, or unsupported features. Promotional text is not used as a search-ranking mechanism.

## Validation

- Both localized names must remain exactly `JustProxy`.
- Names and subtitles must each fit Apple's 30-character limit.
- Keyword strings must fit both 100 characters and a conservative 100 UTF-8-byte limit. Apple currently describes the limit differently across its marketing and reference pages; satisfying both avoids relying on that inconsistency.
- Keyword entries must be unique within a locale and comma-separated without surrounding whitespace.
- Descriptions must fit 4,000 characters and accurately reflect the existing implementation.
- URLs must remain identical to the published support and privacy URLs.
- No application build, test suite, dependency, or source change is required to review this text.

## Publication

Version 1.0.1 is already released. Apple documents subtitle updates as part of a new version submission; language changes also require an editable app state. The user authorized applying this metadata and submitting it for review, so the release uses the next patch version, 1.0.2, and build 9.

The app source and resources match the previously verified 1.0.1 build 8. Only marketing/build values change in the Xcode project. The release reuses the existing 64-test verification after comparing all 21 recorded release input hashes, and independently verifies the new archive and IPA identity, signature, resources, and debug symbols. Future public version changes still require user authorization.

For the approved release, keep the actual Chinese UI visible in screenshots. Reuse valid existing screenshot assets where Apple permits primary-language fallback; do not suggest that the binary has an English interface.

After release, verify the saved metadata, territory availability, ID-based public lookup, and exact-name search separately. Confirm that a native US App Store search for `justproxy` returns the correct application, and check that its product page opens. A successful metadata update does not prove that indexing or device downloads work. Record the check time and distinguish public Search API results from the native App Store experience. Do not claim that App Store review approval fixes the separate China mainland ICP requirement.

## References

- [App Store search](https://developer.apple.com/app-store/search/)
- [Creating your product page](https://developer.apple.com/app-store/product-page/)
- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Localize app information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information)

