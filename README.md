# 4everSwingTimer

Swing timer bars for **WoW: Forever** — main-hand, off-hand and ranged, in one
moveable stack.

Unlike skins of the game's built-in swing timer, 4everSwingTimer is driven by
[LibClassicSwingTimerAPI](https://github.com/Ralgathor/LibClassicSwingTimerAPI),
which reconstructs your swing cycle instead of just re-anchoring at each swing.
That means the bars also show what happens *between* swings:

- cast-completion swing resets (the bar turns red and shakes, like the
  game's interrupted cast bar, then restarts),
- paused swings (desaturated, dimmed),
- clipped swings,
- movement-cancelled Auto Shot reschedules,
- the main-hand / off-hand swing delta for dual wielders.

The library ships embedded — no separate installation needed.

## Bars

| Bar | Shown for |
|---|---|
| Main Hand | melee auto-attacks |
| Off Hand | dual wielding |
| Ranged | Auto Shot / wand |

Visibility modes (like the game's own swing timer): *While swinging*, *In
combat*, or *Always* (when the hand has a weapon equipped). Bar style: *Native*
(reuses the game's own swing timer art) or *Flat* (plain colored bars).

## Commands

| Command | Action |
|---|---|
| `/4everswingtimer` (alias `/everswing`) | open settings, or run a subcommand |
| `... unlock` / `... lock` | show the drag overlay / lock the bars |
| `... test` | animate a fake 2.0s swing on all enabled bars |
| `... reset` | reset the bar position |

Settings are per-character and also available under Game Settings > Addons.

## The game's own swing timer

WoW: Forever ships its own swing timer bars (`showSwingTimer`). If both are
enabled you will see two sets of bars. To keep only these:

```
/console showSwingTimer 0
```

You will get a one-time chat hint about this if the native bars are on.

## FAQ

**The bar finished early after I parried an attack.** Correct-ish: on WoW:
Forever no addon-facing API exists for parry haste mid-swing (a request is filed
with Blizzard), so the library reflects a hastened swing at the next swing
anchor. The bar can overshoot by up to one swing and then self-corrects.

**I changed weapons and the current bar kept the old speed.** On WoW: Forever
the engine applies new weapon speeds at the next swing, so an in-flight swing is
never rescaled. The next swing starts with the new speed.

**No off-hand bar?** You need a weapon in both hands. **No ranged bar?** Equip a
ranged weapon and start Auto Shot.

**Target swing timer?** WoW: Forever provides no API for target swings, so
there is nothing to show — the addon is player-only on purpose.

## Requirements

- WoW: Forever (the Forever beta client, interface 16000+).

## Development

Design spec, verification checklist and roadmap: `docs/SPEC.md`. The addon holds
no swing math of its own — everything comes from the library's
`UNIT_SWING_TIMER_*` events; the bars only compute `expirationTime - now`.

License: GPLv3 (see `LICENSE`), same as the library.
