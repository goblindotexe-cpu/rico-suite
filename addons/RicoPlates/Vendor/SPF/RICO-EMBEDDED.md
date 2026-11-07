# Embedded navigation fallback

Generated from the documented Rico-compatible Shortest Path Forever v1.22.38
source. See `RICO-INTEGRATION.md` for the upstream release and compatibility changes.

This bundle is loaded by the already registered RicoPlates addon, so the player
can activate newly installed navigation using `/reload` rather than restarting
the client. It does not use loadstring, execute remote code, synthesize addon
events, or access another addon's private table.

Changes relative to that source:

- Lua chunks are gated and receive a separate provider namespace plus the host
  addon name for its normal ADDON_LOADED initialization.
- A standalone runtime already loaded (including an incompatible/partial one)
  suppresses all embedded chunks, preserving one runtime and existing ownership.
- Dedicated RicoPlatesNavigationDB and RicoPlatesNavigationCharDB variables keep
  embedded persistence separate from the standalone addon.
- Virtual XML template names are prefixed RicoPlatesNavigation to avoid naming
  collisions even when a standalone provider is loaded.
- Media references and provider-specific metadata use the embedded location and
  original provider version/website rather than RicoPlates metadata.
- The public provider carries RicoEmbedded={host="RicoPlates",version="v1.22.38"}
  only after its API and terrain-verification bridge are present.

The upstream GPL-3.0-or-later licence, credits and third-party notices are retained.
The terrain-verification patch and privacy defaults are unchanged from the
documented original Rico-compatible dependency.
