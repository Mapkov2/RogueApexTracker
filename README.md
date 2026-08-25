# Rogue Apex Tracker

Rogue Apex Tracker is a small standalone World of Warcraft Retail addon for
Subtlety Deathstalker rogues. It measures whether an Ancient Arts empowerment
after Darkest Night happened inside a real Shadow Dance.

The tracker records an attempt only when Ancient Arts becomes active after
Darkest Night. The attempt is successful only while the actual Shadow Dance
buff is active. It displays encounter and session totals, success percentages,
and stores separate history snapshots for combats, boss encounters, and
keystone dungeons.

Rogue Apex Tracker does not require MidnightSimpleUnitFrames or another
framework. It uses Blizzard Cooldown Manager item state for the tracked buffs
and does not register direct `UNIT_AURA` traffic. The optional target rule uses
the addon's own visible-nameplate roster and checks Eviscerate range every 0.2
seconds while that rule is enabled. Unknown range snapshots fail closed.

## Features

- Subtlety Deathstalker eligibility gate
- Darkest Night to Ancient Arts attempt detection
- Real Shadow Dance success detection
- Optional strict 1-3 in-range target rule
- Encounter and reload-safe session statistics
- Last Combat, Encounter, and Keystone history
- Movable and lockable display
- Configurable fonts, outlines, colors, sizes, scale, and background
- Embedded LibSharedMedia support
- Hover previews for font and texture menus
- Blizzard Addon Compartment support
- Native Ancient Arts/Nightblade addon icon

## Install

Download the release ZIP and extract it so this exact file exists:

`World of Warcraft/_retail_/Interface/AddOns/RogueApexTracker/RogueApexTracker.toc`

Restart World of Warcraft, enable **Rogue Apex Tracker**, and log in.

## Commands

- `/rat` or `/rogueapex` - open the options
- `/rat lock` - lock the tracker
- `/rat unlock` - unlock and drag the tracker
- `/rat preview` - toggle preview statistics
- `/rat reset` - reset the current encounter and session statistics
- `/rat history` - open the history browser
- `/rat clear` - clear stored history
- `/ratmenu` - open the options directly
- `/rathistory` - open the history browser directly

## Support

The bottom of the options menu contains copy-link buttons for:

- [Patreon](https://www.patreon.com/cw/MidnightSimpleUnitframes)
- [PayPal](https://www.paypal.com/ncp/payment/H3N2P87S53KBQ)
- [Ko-fi](https://ko-fi.com/midnightsimpleunitframes#linkModal)

## Target-count rule

When **Count Darkest Night only below 4 targets** is enabled, an APEX attempt
counts only with one to three visible hostile nameplates in Eviscerate range.
Four or more targets, missing nameplates, and unknown range results do not
count. Disable the option if you do not want nameplate range sampling.

## Session behavior

Encounter and session counters survive `/reload`. A full World of Warcraft
client restart or the **Reset statistics** action starts a new session. Stored
history is independent and remains until it is cleared or exceeds the
configured per-type limit.

## License

The addon code is released under the MIT License. Embedded libraries retain
their original licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

World of Warcraft and its artwork are trademarks or copyrighted works of
Blizzard Entertainment. This project is not affiliated with or endorsed by
Blizzard Entertainment.
