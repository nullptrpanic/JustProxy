# Bilingual App and Store Presentation

Status: Implemented for the authorized 1.0.3 (build 10) release on November 15, 2026. App Review submission is authorized. The user authorized committing and pushing all project changes to dev and will merge dev into master. No pull request is required. The website deploys after that merge.

## Intent and agreed behavior

Ship one JustProxy app containing English and Simplified Chinese. The user selected the system/app language preference as the source of language selection, with English when no supported language matches. The app name stays exactly `JustProxy`.

The scope includes the app interface, accessibility labels, system permission descriptions, in-app privacy information, the client connection guide, the public support/privacy website, and App Store text and screenshots. The user also wants Chinese store presentation for China mainland and English presentation for international markets.

App Store presentation follows Apple's storefront and language-selection rules. A Chinese localization can also be shown to a Chinese-language customer in a supporting international storefront, including the United States and Singapore. The implementation can provide English as the international default and preserve Chinese content for China mainland; it cannot guarantee a strict country-only language split for every customer in the same app listing.

## Baseline evidence before implementation

- SwiftUI screens contain Chinese literals. State labels, listener labels, and failures also pass through ordinary `String` values, so extracting only `Text` literals would leave gaps.
- The project development language is `zh-Hans`. No string catalog or localized string files currently provide a full English interface.
- `PrivacyView.swift` contains offline Chinese privacy information. Its website link points to the existing `/JustProxy/privacy/` URL.
- `ConnectionGuide.html` contains Chinese markup and dynamic text. Its existing JavaScript selects the accessing device's platform, not its language.
- `website/index.html` and `website/privacy/index.html` are Chinese static pages. The Pages workflow deploys only `website/` from `master`.
- A read-only App Store Connect check on November 15, 2026 returned `READY_FOR_SALE` for version 1.0.2. The primary metadata locale is `zh-Hans`.
- Version 1.0.2 has `zh-Hans` and `en-US` metadata. The Chinese localization owns one completed `APP_IPHONE_61` screenshot; the English localization has no independent screenshot set. Its description accurately states that the current app interface and guide are Chinese.

## Approaches

1. **Native language preferences and one bilingual package — selected.** Use Apple's localization support and the browser's language preferences. This supports users' language choices without location access, a country lookup service, or separate app variants.
2. **Device region as the language selector — not selected.** A configurable region is not physical location and can conflict with the language a user wants to read.

Within the selected approach, use native string catalogs for the app and small, page-local bilingual resources for HTML. A shared runtime localization framework or a new website generator would add complexity without useful benefit for the current two-language scope.

## App resources and behavior

- Add English and Simplified Chinese string resources. Set the development fallback to English and verify both resources are present in the built bundle.
- Use native localized SwiftUI text for view literals and `String(localized:)` or equivalent native APIs where ordinary strings are required. Include model state, network selection, failures, copy feedback, accessibility labels, and interpolated text.
- Localize complete sentences instead of concatenating translated fragments. Use appropriate plural forms for connection counts and preserve Foundation's locale-aware number/byte formatting.
- Localize the existing local-network permission explanation through InfoPlist localization. Keep the same permission behavior.
- Honor the iOS per-app language preference. A new in-app language settings page is unnecessary.
- Preserve the current dark appearance, main power control, green running indicator, and page structure. Make only layout adjustments needed to fit English text or larger accessibility text.
- Keep technical values such as IP addresses, port numbers, protocol names, host names, and connection data unchanged.

## Privacy and web content

- Translate the existing privacy statements without changing the app's data practices or adding promises. The in-app explanation remains available offline.
- Keep the public contact email and existing support/privacy URL paths. Keep review-only contact information out of all public assets.
- The connection guide follows the accessing client's browser language, independently of the proxy-hosting iPhone. Preserve platform detection, manual platform tabs, address copying, real endpoint substitution, and HTTP behavior.
- Public support and privacy pages use the browser's preferred supported language, with English as the fallback. Provide a visible `中文 / English` control and explicit language URLs using a query parameter, while preserving the existing base URLs.
- Links opened from the app can carry its selected language to the website. Explicit language selection takes priority over browser detection and remains consistent while navigating between support and privacy pages.
- Keep both translations available as static content. Pages remain readable without a translation service, and no new analytics or country lookup is introduced. The website still needs its own Pages deployment; it is not updated by uploading an IPA.
- English and Simplified Chinese are the provided translations. Language-tag normalization and fallback cases must be checked explicitly; do not claim a separate Traditional Chinese translation.

## App Store presentation

Prepare a complete Chinese localization and a complete English localization, each with matching descriptions, subtitles, keywords, release notes, support/privacy destinations, and independently uploaded screenshots.

Use `en-US` for the US storefront and `en-GB` for international storefronts that support English (U.K.). Include `en-AU` and `en-CA` to provide explicit English assets for those storefront language variants while the primary metadata locale remains Chinese. These locales share English copy and screenshot assets and do not require separate app binaries.

Capture actual screens from the localized app. Each language should cover the same three useful states:

1. The running proxy and its address.
2. Listening-address selection with real available interfaces.
3. Session traffic and recent connections from controlled real requests.

Do not ship demo traffic or simulated interface choices to produce these screenshots. Do not add an English heading over a Chinese interface and present it as an English app. Keep the real current design rather than creating a new marketing layout. Include an English screenshot at the size corresponding to the existing `APP_IPHONE_61` set, and validate any additional required sizes against Apple's current specifications.

After the binary is bilingual, update the English description's current Chinese-only statement. The existing live listing remains truthful until that release is ready. Name, pricing, territories, and technical product claims stay as configured unless a separate request changes them.

### Store rollout dependency

Apple requires the destination primary language and independently uploaded screenshots in that language to have passed review in a previous version. The existing English metadata is approved, but its inherited Chinese screenshots do not satisfy the independent English screenshot prerequisite.

1. Prepare a bilingual binary and submit matching Chinese/English store text and independent screenshots in the next authorized release. Include international English metadata as needed for storefront coverage while the primary locale is still Chinese.
2. After Apple approves the English screenshot assets, change the primary metadata locale to English in a subsequent eligible update. Keep the Simplified Chinese localization for China mainland. Verify API eligibility rather than bypassing it or assuming approval alone is sufficient.
3. Verify the published presentation by storefront and language separately. An English default is not a guarantee that every user outside China sees English; Apple may select an available Chinese localization for that user's preferences.

This sequence uses one app and bilingual packages. It does not require separate domestic and international apps. Version/build selection, upload, changing the primary locale, website publication, and review submission are release actions to be carried out when requested; this design does not automatically authorize a new publication or Git push.

## Verification and acceptance

- Build with DerivedData under `build/`; inspect the built localized resources and localized permission text.
- Check the app under English, Simplified Chinese, and an unsupported preferred language with no supported secondary preference. Verify explicit per-app language selection and English fallback.
- Inspect the main screen, listener sheet, traffic page, privacy page, errors, and accessibility text for untranslated strings and truncation. Check a small iPhone layout and larger text sizes.
- Check browser language selection, explicit language selection, mobile/desktop platform tabs, copying, and support/privacy navigation in both languages. Check the client language independently of the hosting phone's language.
- Run existing connection-guide HTTP tests because its HTML will change. Preserve response status, real endpoint rendering, content length, HEAD behavior, and exclusion from proxy traffic. Run relevant proxy regression checks if localization touches failure-producing core files.
- Use controlled real traffic for screenshots. Inspect every localized screenshot and confirm localized metadata refers to capabilities present in the submitted binary.
- Before a requested store submission, verify independent screenshot sets, delivery completion, metadata lengths, and the intended version/build. Re-read the resulting review state.
- Keep all generated screenshots, builds, logs, and verification records under ignored `build/`. Keep source documentation in English and leave changes uncommitted unless requested.

## References

- [Apple: Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Apple: How iOS determines the language for your app](https://developer.apple.com/library/archive/qa/qa1828/_index.html)
- [Apple: Localize app information and change the primary language](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information/)
- [Apple: App Store localizations by country and region](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)
- [Apple: Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [MDN: Browser language preferences](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/languages)
