# RicoPlates integration

This is Shortest Path Forever **v1.22.38**, by Cillian Berragan, with a small
RicoPlates compatibility patch. The upstream licence and all bundled notices,
assets and navigation data are retained. Upstream: https://github.com/cjber/shortest-path-forever

Original release archive: `ShortestPathForever-v1.22.38-forever.zip`

SHA-256: `adce5d713e4fb91cc0997aa1c1b3a06610d185434ac3afc623de3049e9a52293`

Changes:

- `RicoPathBridge.lua` exposes a small status API and filters unverified walking
  sketches from map/minimap lines and direction guidance for **RicoPlates and
  RicoMining routes**. A verified walk requires measured terrain-search points, no
  search error, and a validated point sequence. Other owners retain upstream
  behavior and ownership.
- The TOC loads this bridge after the upstream modules.
- `Journey/JourneyGuide.lua` permits its existing owned-waypoint clear during
  combat only when RicoPlates has blocked an unverified walking leg. Calls are
  protected with `pcall`; another owner's waypoint is never cleared. This is
  not a general combat visibility mode: verified routes remain visible.
- A newly requested RicoPlates journey starts at the player's position and
  replaces the previous native waypoint. Its flight instructions point to the
  departure flight master before boarding. The planner offers Hearthstone only
  when the bind point itself satisfies the destination's arrival distance.
- Fresh-install defaults disable peer sharing, travel-stat recording/sharing,
  automatic RestedXP following, corpse guidance, first-run popup and the TomTom stand-in. Existing saved choices
  are not overwritten. These can still be changed in the upstream settings.

This provides map/minimap routes and a direction arrow, not a line rendered
on the 3D terrain. Navigation coverage follows the included meshes; no route
is guaranteed where a terrain search fails. No movement is automated.

Updating this addon from another source may remove the patch. RicoPlates then
refuses to start a route through this integration until a compatible bridge is
available. The original archive is listed in the upstream releases at
https://github.com/cjber/shortest-path-forever/releases/tag/v1.22.38.
