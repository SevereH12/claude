# Prompt 4: add the next world, using the unused maps (run once per world)

Follow the rules in `docs/prompts/README.md`.

**Needs prompt 2 and worlds**: `requiresBottle` must be on `ZoneDef`, and
`Config.WORLDS`, `Kit.portal` and `Systems/Travel` must exist. If any is
missing, stop and tell the user.

Each run turns one unused world style into a whole new **world**: its own
hub with a spawn and sell station, three zones in that style's own looks,
and a "Coming Soon" teaser, built far away from the other worlds. The
previous world's hub gets a portal to it that opens once you own the
world's bottle, and the new hub gets a portal back. Volts, bottles and
boots carry over; each world adds new bottles and boots so its zones have
something to aim for.

Do the first row in the plan that isn't ticked, and tick it when you're
done.

## The plan

| Done | World id | Name | Style | Opens with | Offset (x) |
| --- | --- | --- | --- | --- | --- |
| [x] | Voltcliff | Voltcliff Works | StormPunk | Storm Cell (tier 5) | 5000 |
| [x] | Stormspire | Stormspire Isles | SkyIsles | Dynamo Drum (tier 7) | 10000 |

Zones (all `world = <World id>`, `order` 1 to 3):

| World | id | Name | Theme | Mode | Volts per charge | Strike interval | Size (w x d) | Floor | Needs bottle |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Voltcliff | Yard | Generator Yard | Default | Shared | 60 | 0.9 | 104 x 116 | 8 | Storm Cell (5) |
| Voltcliff | Tidewire | Tidewire Beach | Beach | Shared | 150 | 0.8 | 96 x 104 | 4 | Tempest Tank (6) |
| Voltcliff | Thunderhead | Thunderhead Mesa | Canyon | Single | 500 | 1.2 | 100 x 110 | 20 | Dynamo Drum (7) |
| Stormspire | Spire | Rune Spire | Default | Shared | 1,200 | 0.9 | 104 x 116 | 12 | Dynamo Drum (7) |
| Stormspire | Cloudshore | Cloudshore | Beach | Shared | 3,000 | 0.8 | 112 x 132 | 4 | Rune Cell (8) |
| Stormspire | Ember | Ember Mesa | Canyon | Single | 10,000 | 1.2 | 96 x 104 | 20 | Storm Core (9) |

New tiers (appended to `BOTTLES` and `BOOTS`):

| World | Bottles (capacity / price) | Boots (bonus / price) |
| --- | --- | --- |
| Voltcliff | Tempest Tank 250 / 40,000; Dynamo Drum 600 / 200,000 | Coil Striders +7 / 35,000; Arc Runners +8 / 150,000 |
| Stormspire | Rune Cell 1,500 / 1,000,000; Storm Core 4,000 / 5,000,000 | Sky Treads +9 / 600,000; Cloud Walkers +10 / 3,000,000 |

Numbers are suggestions. Zone ids must be unique across worlds. If
`Layout.plan` says slots overlap or a connector is too steep, change only
this world's zone sizes or floors (sizes the style's own preview already
uses are safe). Boots bonuses must keep in-zone speed below
`WALK_SPEED_OUTSIDE`.

## Step 1: review the style you're using (before writing code)

- Run `tools/check_world.sh <Style> <scratch dir>` (a preview: the first
  world's zones in that style) and look at its top and side renders once.
- Read that style's "Zones" and hub sections in `docs/styles/<Style>.md`,
  plus its `init.luau` and `Hub.luau`. Open other files only when a
  function you'll call needs them.
- Write down, in a few lines in your reply:
  - where its hub can stand a portal: a `Kit.PORTAL_SPACE` circle beside
    the spawn, clear of every exit lane and hub prop (WeatherLab uses a
    cottage gap, StormPunk a quiet-bearing prop slot)
  - whether any zone floor would equal the style's `hubFloor` (StormPunk's
    flat catwalks flicker there; pick floors that don't)
  - anything its `atmosphere` sets up that the zones need (only the first
    world's atmosphere runs; others get it lazily or not at all)

## Step 2: build it

1. **Config**: append the world to `WORLDS` (id, name, tagline, style,
   `requiresBottle`, a colour no other world uses, `offset` from the
   plan), add its zones, and append its bottles and boots.
2. **The style's hub**: build one `Kit.portal` for each `ctx.portals`
   entry beside the spawn (the way back now; an onward one when a later
   world exists). The previous world's hub builds its onward portal from
   `ctx.portals` already.
3. Don't touch the other worlds' styles. Small, backwards-compatible
   changes to the new world's own style are fine.
4. Tick this world's row in the plan above.

## Step 3: review before pushing

Don't push until all of this passes. Fix anything that fails and review
again (at most twice).

- `stylua src` and `selene src` are clean.
- `tools/check_world.sh Game <scratch dir>` passes for every world: build,
  gameplay tests (spawns, portals leading where they say), walkcheck (spawn
  to every zone, camp, sell area and portal, per world) and flickercheck.
- `lune run tools/harness/test_progression.luau` passes (the HUD goal past
  the last open world is the next world).
- Look at the new world's top and side renders and check that:
  - the portal stands beside the spawn, clear of lanes and props
  - the zones sit on the spiral with the teaser after them
  - each catch floor is flat and clear
  - nothing overlaps
- If the Studio MCP is connected, take one look in play mode: walk through
  the portal with the TEST Volts and the right bottle.
- In your final message, list what you checked, with the render images
  attached. Then commit and push.
