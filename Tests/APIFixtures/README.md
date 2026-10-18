# Tests/APIFixtures

Recorded answers of the HTTP APIs the app calls, used by `Tests/MacDashboardTests/IPSWTests.swift`
through `apiFixturesRoot` (`TestSupport.swift`). They live outside `Tests/Fixtures/` because that tree
admits only `ParsedCommand` directories of `.txt` captures (its README, enforced by
`ParserFixtureTests`). Tests never use the network; `IPSWLiveCanaryTests` (opt-in, `MACDASH_LIVE=1`)
is the only code that compares these shapes with the live services.

All content is public catalogue data (model identifiers, build numbers, Apple CDN URLs, checksums);
nothing device- or user-specific, so nothing was scrubbed.

## ipswme/ — `GET https://api.ipsw.me/v4/device/<identifier>?type=ipsw`, captured 2026-10-15

- `device-iphone18-2-2026-10-15.json` — iPhone 17 Pro Max, trimmed to 3 builds (24A446 signed, 24A437, 23G90).
- `device-iphone10-3-2026-10-15.json` — iPhone X (Global), trimmed to 3 builds: 20H392 (signed), 16D57
  (empty `sha256sum`, plain-http URL), 15B93 (plain-http URL).
- `device-iphone1-1-2026-10-15.json` — iPhone 2G, its single build (`releasedate: null`).
- `not-found-2026-10-15.json` — the HTTP 404 body for an unknown identifier.

Trimming removed whole entries of `firmwares` only; every kept object is verbatim.

## apple/ — `GET https://itunes.apple.com/WebObjects/MZStore.woa/wa/com.apple.jingle.appserver.client.MZITunesClientCheck/version`

- `itunes-version-trimmed-2026-10-16.plist` — captured 2026-10-16 (the full answer is ~6.3 MB), trimmed to
  `MobileDeviceSoftwareVersionsByVersion` keys 16 and 17 and three models: `iPhone18,2` (an `Unknown`
  target, a `Restore`, `SameAs` entries), `iPhone16,2`, and `iPhone10,3` (an http 15G77 target under 16,
  the https 20H392 target under 17). Kept entries are verbatim.
