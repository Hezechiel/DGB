# Main menu / UI shell — DGB architecture

> Part of docs/architecture.md — see the index there.

## Main menu / UI shell

`scenes/menu/MainMenu.tscn` (`scripts/ui/main_menu.gd`) — the hub screen
reached on launch and returned to after a match. Pure UI chrome, no match
state — everything here is display/navigation only. Node structure, all
under `Background` (a full-screen `Panel`, the last declared child of the
menu root so it draws over the overlay instances declared above it, see the
draw-order pitfall in `conventions_pitfalls.md`):

- `Background` itself (Oct 2026) — its `StyleBoxTexture` (with a darkening
  `modulate_color`) is the hub backdrop. `main_menu.gd::_apply_menu_background()`
  runs in `_ready()` (so on launch and on every return from a match): it
  `load()`s **one** path from `MENU_BACKGROUNDS`
  (`assets/menu/background/greek/greek_tier1–3.png`) — never preloads all
  three — duplicates the stylebox, sets the texture and overrides it.
  The choice is `_pick_background_path()`, a uniform-random **TEMP** pick;
  by design the tier will follow account level (`game_design.md` §3.13),
  and only that function changes then. The scene's own stylebox texture
  (tier 1) is the editor preview and the fallback when a load fails.
  `texture_filter = Linear` on `Background` (`conventions_pitfalls.md` filtering).
- `NavRail` (`VBoxContainer`, left edge, anchored full-height, x 8–158) —
  `BattlesButton`, `DeckButton`, `PantheonButton`, `ShopButton`,
  `RewardsButton`, a `Control` spacer, `ExitButton`. All are `TextureButton`s;
  the five rail buttons share one atlas (`main menu_rail buttons.png` /
  `_pressed.png`, `AtlasTexture` regions). **The rail never hides for tabs**,
  only under the fullscreen overlays (Settings, Credits, Card Detail).
  Battles / Deck / Pantheon / Shop are **tabs** (Oct 2026): `main_menu.gd`
  sets `toggle_mode = true` and one shared `ButtonGroup` on them in `_ready()`,
  so exactly one is pressed and its `texture_pressed` marks the active tab (no
  extra art). `RewardsButton` is not a tab: it shows the coming-soon toast and
  the selected tab does not change.
- `TopBar` (`HBoxContainer`, top edge) — `CurrencyGroup` (a `ColorRect` +
  static `"0"` `Label`, placeholder), `MailButton`/`GiftButton` (same
  flat-color placeholder pattern as the nav rail), `SettingsButton`
  (`TextureButton`, opens `SettingOverlay`).
- `MainContent` (`Control`, Oct 2026 — was an `HBoxContainer`) — the page
  area between the rail and the right edge, below `TopBar` and above
  `FooterBar` (`offset_left = 166`, `offset_top = 50`, `offset_bottom = -30`),
  so the TopBar (currency, mail, gift, settings) and the footer are never
  covered by a tab. Its children are full-rect **tab pages**, exactly one
  visible at a time:
  - `HomeView` (`HBoxContainer`, separation 20) — the Battles tab, active when
    the menu opens. `HeroShowcase` (`Control`, `size_flags_horizontal = 3`)
    holds a single `AnimatedSprite2D` (`ZeusIdle` — name kept, it shows any
    god) playing the **active deck god's** idle animation
    (`PlayerProfile.get_deck_hero()` → `HeroData.sprite_frames`, `iddle_left`
    then `idle_left`), set by `main_menu.gd::_apply_showcase_god()` in
    `_ready()` and again on `PlayerProfile.profile_changed`. A god without
    frames or an idle clip falls back to the scene's own `frames_zeus.tres`;
    one shared scale (1.2) for every god. `BattleCard` (`TextureButton` with
    `BattleButtonSparks`, `size_flags_vertical = 4`) is the sole entry point
    into `PreMatchFlow.tscn` (`battle_scene.md`).
  - `DeckOverlay`, `PantheonOverlay`, `ShopOverlay` — the other three tabs
    (see "Tab pages" below).
- `ComingSoonToast` (`PanelContainer`, hidden by default) — generic "<X> —
  coming soon" toast for any unimplemented nav-rail/top-bar button, shown
  via `main_menu.gd::_show_coming_soon(feature_name: String)`. Debounced
  with a `_toast_token: int` counter: each call increments the token and
  only the matching deferred hide (`get_tree().create_timer(...).timeout`)
  actually hides the toast, so rapid taps across different placeholder
  buttons extend the visible window instead of an earlier timer hiding it
  mid-read. Reusable pattern for any future auto-hiding transient UI.
- `FooterBar` (`HBoxContainer`, bottom edge) — title, `•`, `VersionLabel`
  (reads `ProjectSettings.get_setting("application/config/version", ...)`
  at `_ready()`, backed by a real `config/version` project setting — never
  hardcoded in two places), `•`, `ServerStatusLabel` (static placeholder
  text, no real server/backend yet).
- `SettingOverlay` / `CreditsOverlay` / `CardDetail` — the **fullscreen
  overlays**, siblings of `Background` declared *before* it in the tree (see
  the draw-order pitfall in `conventions_pitfalls.md`). All start `visible = false`; `main_menu.gd`
  calls `move_to_front()` on the one it opens and hides the menu chrome via
  `_set_menu_chrome_visible(false)` (`NavRail` + `MainContent` together). Only
  `MainContent` is hidden, not the page inside it, so closing an overlay
  returns to the same tab in the same state. Settings holds a `CreditsButton`
  that closes Settings and emits `credits_requested`, which `main_menu.gd`
  answers by opening Credits — the two are never open at once. Settings and
  Credits are still wired with `[connection]` entries in `MainMenu.tscn`;
  `CardDetail` is connected in code and opened by both the Pantheon and the
  Deck tab's `card_detail_requested`. Known gap: in a match the HUD does not
  listen to `credits_requested`, so the Credits button there closes the pause
  screen without resuming — hide it in the arena or wire it.
- **Tab pages** — `DeckOverlay`, `PantheonOverlay`, `ShopOverlay` (Oct 2026:
  no longer overlays, despite the names; a rename to `*View` is planned and
  should be done in the editor). Instanced under `Background/MainContent`,
  full rect, **no Close button**. Contract: `activate()` (rebuild +
  `visible = true`) and `deactivate()` (reset transient state +
  `visible = false`); no `closed` signal. `main_menu.gd` owns the switching:
  `enum Tab { HOME, DECK, PANTHEON, SHOP }`, `_tab_pages` / `_tab_buttons`
  dictionaries, `_request_tab(tab)` (button `pressed`) → `_switch_tab(tab)`
  (deactivate the old page, activate the new one; `HomeView` has no methods,
  so plain `visible`). Logs `[menu] tab: …`.
  - `shop_overlay.gd` — lists `CardDB.list_pack_ids()`; opening a pack rolls
    with `PackRoller`, grants through `PlayerProfile.grant_cards()` (one call
    per pack) and shows a list reveal (NEW / +1 copy). `deactivate()` returns
    to the pack list. Plain default-theme controls, no art yet.
  - `pantheon_overlay.gd` (formerly `encyclopedia_overlay.gd`) — a faction tab
    per pantheon found in the data; sections Gods / Units / Spells of
    `DeckTile`s (locked ones tappable). Gods are listed regardless of
    `obtain_source`; cards with `obtain_source = 0` are hidden. A god tile
    shows `HeroData.card_art`, falling back to the first idle frame
    (`DeckTile._hero_texture()`). A tap emits
    `card_detail_requested(id, kind)`; `main_menu.gd` opens the `CardDetail`
    overlay at the menu root (not a child of this page, so it always covers
    the full screen). The page rebuilds on `PlayerProfile.profile_changed`
    while its own `visible` is true — still true under Card Detail, so tile
    notes refresh after a level up. `activate()` rebuilds the faction tabs and
    resets to the first one. Plain default-theme controls.
  - **Deck tab** — see "Deck screen" below.
- Debug keys in the main menu (debug builds only): **F9** reset profile,
  **F10** +1 copy of everything obtainable (and every god), **F11** toggle
  `DebugLog`.

### Deck screen (Oct 2026)

`scenes/menu/deck_overlay.tscn` + `scripts/ui/deck_overlay.gd`
(`class_name DeckOverlay`), tiles `scripts/ui/deck_card_tile.gd`
(`DeckCardTile`, built in code). Layout from the deck-building art, all
stacked in one `VBoxContainer`, scaled to `MainContent` (no fixed card
pixels):

```
DeckOverlay
└── Layout (VBoxContainer)
    ├── GodShowcase      god idle animation (GodSprite) or card_art (GodArt) — view mode only
    ├── DeckPanel        Frame + Margin/DeckBox/{Header, SlotGrid}
    └── CollectionPanel  Frame + Margin/CollectionBox/{CollectionHeader (the bar), PoolScroll/PoolGrid}
```

- **Two modes, instant switch** (`_set_editing()`; a slide animation is a
  possible later step):
  - *View* (default on `activate()`, after Save and after Cancel): avatar on
    top, `DeckPanel` across the full width — header (pantheon logo
    `assets/menu/logos/logo_<faction>.png` via `DeckCardTile.logo_for()`, god
    name, synergy line with live `have / need`, average energy cost) and the
    8 deck tiles (god + 7) in **one row** (`SlotGrid`, a `FitCardGrid` with
    `columns = 8`). Under it the short framed bar shows only **Edit**. A tap
    on a deck tile opens Card Detail; `draggable = false`, so a hold does
    nothing.
  - *Edit* (only via the Edit button — no auto-Edit on tap): avatar hidden,
    `DeckPanel` moves up, the bar shows `CARD COLLECTION`, the filter tabs
    ALL / UNITS / SPELLS, the hint, Cancel and Save, and the collection
    appears below it.
  - Heights are stretch ratios, not pixels (the grids deliberately report no
    minimum size): view `DeckPanel : GodShowcase = view_deck_ratio : 1`
    (export, 1.2), edit `CollectionPanel : DeckPanel =
    edit_collection_ratio : 1` (export, 1.3); in view mode
    `CollectionPanel` drops `EXPAND` so it collapses to the bar.
- **Collection** — `PoolGrid` (`GridContainer`) inside a horizontal-only
  `PoolScroll`, **two rows** (`POOL_ROWS`), filled **column by column** so the
  sort order (gods first under ALL, then owned → cost → id, locked last)
  reads left to right in pairs. **It lists only what is not in the draft**:
  `_pool_card_ids()` skips `_draft_cards` and `_pool_hero_ids()` skips
  `_draft_hero` (Clash Royale model; there is no "IN DECK" state in the
  collection any more). Every draft change rebuilds it
  (`_refresh_draft_view()` → `_rebuild_pool()`), so a card replaced in the
  deck reappears in its sorted place; the horizontal scroll is saved before
  and restored after the rebuild (filter change and entering Edit still
  reset it to 0). A `GridContainer` fills row-major, so
  `_rebuild_pool()` places entry `i` at cell `(i % rows) * cols + i / rows`
  and puts a mouse-ignoring filler `Control` in the empty bottom cell when
  the count is odd. Tile height = (scroll height − scrollbar space − row gap)
  / 2, width from `CARD_ASPECT` (0.82) via `DeckCardTile.width_for_height()`.
- **Frames** — the two panels are framed by
  `assets/menu/deck/frame_ninepatchrect.png` (152×127, transparent centre)
  through a `Frame` node (`ScaledNinePatch`, first child of each
  `PanelContainer`, panel stylebox `StyleBoxEmpty`), patch margins 52/46,
  `patch_scale = 0.7`, plus `fill_color` / `fill_inset` for the dark panel
  fill under the frame (inset in source px, scaled like the patches). Cards
  have **their own painted frame** in the art: `DeckCardTile` draws the art
  whole (`KEEP_ASPECT_CENTERED`, no crop) and only overlays the cost badge
  (top-left), the pantheon logo, `Lv. N`, the status (LOCKED / FORBIDDEN)
  and, in the collection, the copies progress bar. The **logo** sits in the
  bottom-right corner, large (`LOGO_SIZE` 0.5 of card width) and partly past
  the card edge (`LOGO_OVERHANG` 0.25), cropped at the card's outer edge by a
  `clip_contents` `_logo_clip` the size of the card (so it never covers the
  progress bar). `Lv. N` is drawn **over** the logo with an outline of
  `LEVEL_OUTLINE_RATIO` (0.45) × font size. A dedicated painted corner asset
  can replace the code crop later if needed.
- **Input (both modes):** **tap** on any tile (deck slot or collection;
  owned, locked or forbidden) emits `card_detail_requested(id, kind)`, which
  `main_menu.gd` answers with the same fullscreen `CardDetail` overlay the
  Pantheon tab uses; closing it returns to the same mode and draft. There is
  **no tap-to-select / tap-then-tap** any more. **Edit mode only:** a swipe
  scrolls the collection; **holding** an owned, allowed card for
  `hold_to_drag_time` s (export, 1.0) charges the gold glow (the glow exists
  only as this hold feedback, appearing after `HOLD_FEEDBACK_DELAY` 0.15 s),
  then the card lifts — the source tile goes fully transparent so its cell
  stays empty, and a full-size preview (art + cost badge) follows the finger
  via `force_drag()`. Releasing over a valid slot places it (`_can_drop_data()`:
  gods only on slot 0, cards only on 1–7, never onto itself); releasing
  anywhere else is Godot's normal drop-cancel — nothing changes and
  `NOTIFICATION_DRAG_END` makes the tile visible again. Slot-to-slot drags
  swap. `_place()` is the only draft mutation (swaps, never a duplicate or
  empty slot). Saves only through `PlayerProfile.set_deck()`. Per-god
  decks: dropping another god on slot 0 loads that god's deck, with a
  Discard / Cancel dialog if cards were changed. Cards the draft god refuses
  are greyed ("Forbidden").
- **Leave guard:** `has_unsaved_changes()` (Edit mode and card edits or a
  draft god other than the active one). When true, `main_menu.gd`'s
  `_request_tab()` re-selects the Deck rail button and calls
  `confirm_leave()`, which reuses the same Discard / Cancel dialog
  (`_pending_leave` tells the two uses apart). Discard → `deactivate()` +
  `leave_confirmed` → the pending tab opens; Cancel → stays in Edit.
  `deactivate()` itself silently drops an unsaved draft.
- Not built: the Deck picker (Deck 1 / 2 / …) from the art, a "Use" button in
  Card Detail, auto-scroll while dragging near the collection edge,
  fly-back / landing animations, Edit-button art (plain `Button` like Save / Cancel), the
  mode-switch animation. The Pantheon tab still uses the older `DeckTile`.

### Framed overlays (Oct 2026)

`scenes/menu/framed_overlay.tscn` + `scripts/ui/framed_overlay.gd`
(`class_name FramedOverlay`) is a **base scene**; `setting_overlay.tscn` and
`credits_overlay.tscn` are **inherited scenes** of it (scene inheritance, so
each one's content stays editable and previewable in the editor). A new
framed screen = a new inherited scene + `title_text` + its own children under
`ContentArea`. Base tree:

- root `FramedOverlay` (full rect, `mouse_filter` STOP — blocks taps behind,
  including tap-to-move in the arena; `texture_filter = Linear`, `conventions_pitfalls.md`)
- `Dim` (`DimWithHole`, `scripts/ui/dim_with_hole.gd`) — first child, draws
  `dim_color` around `hole_source` (`DimHole`) grown by `hole_pad` (`conventions_pitfalls.md` pitfall)
- `FrameFit` (`AspectRatioContainer`, ratio of the art, FIT, centered) →
  `FrameRoot`, whose children are anchored by **fractions of the art**, so
  they stay on their painted regions at any screen aspect:
  - `DimHole` — marker only, the window's bounding box
  - `FrameArt` — `assets/menu/settings/settings_frame_blank.png` (no title,
    one asset for every framed screen)
  - `TitleLabel` — on the title plate; CinzelDecorative-Black, gold
    `Color(1.0, 0.82, 0.3)`, black outline 3, uppercase, the end-of-match
    banner style. `set_title()` / `_fit_title()` shrink the font from 26 to at
    least 14 px so any title fits the plate; re-fits on `resized`.
  - `GodWindow` / `GodIdle` (`AnimatedSprite2D`, `process_mode ALWAYS`, `conventions_pitfalls.md`) —
    the active god's `iddle_left` (`PlayerProfile.get_deck_hero()`), scaled
    by one shared factor from `GOD_REF_FRAME_H = 400` (so gods keep their
    relative sizes from the art), bottom-centred on the podium, drawn
    *behind* `FrameArt` so the columns overlap it. Tunables `god_height_fill`,
    `god_foot_nudge`.
  - `ContentArea` (`MarginContainer`) — empty slot over the marble.
  - `CloseButton` — `TextureButton` at the frame's top-right corner
    (group `ui_sfx_close`, `process_mode ALWAYS`). **Known gap:** it has no
    texture, and `settings_frame_blank.png` no longer paints an X, so the
    hit area is invisible — give it `assets/menu/close.png` (as Card Detail
    does).
- API for derived scripts: call `super()` first in `_ready()` (`conventions_pitfalls.md`), call
  `_frame_opened()` from `open()` and `_frame_closed()` from `close()`,
  override `_on_frame_close_pressed()`. Exports: `title_text`,
  `frame_texture` (optional per-screen art override, null by default),
  `god_height_fill`, `god_foot_nudge`.
- `SettingOverlay` (`setting_overlay.gd`, `class_name SettingsOverlay`, root
  `process_mode = 2`) keeps its public API (`open(show_return_to_mainmenu_button)`,
  `close()`, signals `closed_requested` / `exit_requested` /
  `credits_requested`): audio rows (label + `AudioControl` slider), lock
  camera, Credits + Main Menu buttons, in a scrollable list. Instanced in
  `MainMenu.tscn` and in `HUD.tscn` (pause screen).
- `CreditsOverlay` (`credits_overlay.gd`) — `title_text = "Credits"`, a
  scrollable role/name list; `open()` / `close()` / `closed`.
- Art rule going forward: frames are painted **without** words and without
  the close X — `assets/menu/close.png` is the standard close button, placed as
  a real `TextureButton` (Card Detail already does this; the framed overlays
  still need it, see the gap above).

### UI Theme — `assets/UI/dgb_theme.tres` (Oct 2026)

One `Theme` for panel and button styles, applied on a **scene root** (today
only `card_detail.tscn`; not project-wide, so older default-theme screens are
unaffected until they are restyled). Type variations:

| Variation | Base | Look |
|---|---|---|
| `StatTile` | `PanelContainer` | `StyleBoxFlat` dark navy, radius 5, 1 px border |
| `DarkStrip` | `PanelContainer` | `StyleBoxFlat` translucent black, radius 4 |
| `LevelBadge` | `PanelContainer` | `StyleBoxFlat` circle, blue fill, gold 3 px border |
| `TabButton` | `Button` | 9-slice `tab_inactive.png` / `tab_active.png` (pressed), Oswald-Bold 17, grey → gold text |
| `GoldButton` | `Button` | 9-slice `upgrade_card_button_active.png`; disabled = `upgrade_card_button_inactive.png` with `region_rect` crop; Oswald-Bold 20, dark text |

Plus `Label` font colour (cream) and the Oswald default font. Rules: a plain
rectangle is a `StyleBoxFlat` (sharp at any size, no texture memory, one place
to tune); only painted detail (gold bevels, ornaments) is a texture, and it is
used as a 9-slice `StyleBoxTexture` on a normal `Button` so Godot draws the
text — `TextureButton` stays for icon-only buttons. Fonts: Oswald (static
Bold / SemiBold / Medium / Regular) for card and stat UI;
CinzelDecorative-Black for framed-screen titles and the end-of-match banner;
Marcellus for older menus.

### Card Detail (Oct 2026)

`scenes/menu/card_detail.tscn` + `scripts/ui/card_detail.gd`
(`class_name CardDetail`) replaced `card_flashcard.tscn` / `CardFlashcard`
with the **same API** — `open_for(id: StringName, kind: StringName)`,
`close()`, signal `closed` — and the same stat formulas (`LevelCurve` via
`PlayerProfile.LEVEL_CURVE`). The old flashcard files are no longer
referenced and can be deleted (delete order: `conventions_pitfalls.md`). Not a `FramedOverlay`:
different frame (`assets/menu/deck/card_detail_blank.png`, no god window).
Root has `theme = dgb_theme.tres` and `texture_filter = Linear`.

- Layout over the frame (fractions of the art, inside an `AspectRatioContainer`
  like the framed overlays): `FrameArt`; `ThemeArt` — a full-canvas
  per-pantheon scenery layer (`FACTION_THEME_ART`: `greek` →
  `deck/themes/greek_theme.png`, `norse` → `nordic_theme.png`; missing key =
  hidden); `CardArt` (`CardData.scroll_texture`, or `HeroData.card_art`
  falling back to the first idle frame; greyed when not owned); `AltArtRow`
  (three "UNK" placeholder slots); `LevelBadge`; `InfoColumn` (name, epithet
  "UNK", Type + Rarity `StatTile`s, description — the card's / god's
  `description` lore intro — beside the scenery, `StatsGrid` of 8 tiles);
  `TabsColumn` (Skills / Details `TabButton`s in a `ButtonGroup`, each pane in
  its own `ScrollContainer` — `SkillsScroll` / `DetailsScroll`, `conventions_pitfalls.md`);
  `UpgradePanel` inside the box painted in the frame; `CloseButton`
  (`close.png`, darkens via `self_modulate` while held).
- **Skills tab:** for a god, `SkillName` shows `HeroData.skill.display_name`
  and `SkillDescription` shows `"Cooldown: Ns"` plus
  `SkillData.get_description()` — the template filled from the skill's
  current `values` (`data_layer.md`), so retuning a number updates the text. Cards and gods
  without a skill show "—". `IconSlot` is still a placeholder `ColorRect`.
  **Details tab:** pantheon, domain, tags, obtain source and, for gods,
  `DeckRules.describe_synergy()`.
- `scenes/menu/stat_tile.tscn` (`StatTile`, `PanelContainer`,
  `theme_type_variation = "StatTile"`) — `set_stat(name, value, delta = "")`;
  the green delta is the gain at the next level (`+62`, or `-0.04s` for a
  god's recovery), shown only when owned and not max.
- Upgrade: the button is disabled unless `PlayerProfile.can_upgrade(id)`;
  pressing it calls `PlayerProfile.upgrade_card(id)` and refreshes (also on
  `profile_changed`). States: not owned → "Locked"; max → "Max level".
- Placeholders are literal `"UNK"` strings in the scene/script (epithet,
  Deploy Time, alternate arts) — `game_design.md` §6 lists what each one
  waits for. The layout is a stop-gap: a readability rework of the Skills
  area is planned.

Two general Control-layout pitfalls surfaced building the main menu — the
draw-order one and the `Node2D`-in-a-`Control` centering one — are filed in
`conventions_pitfalls.md` rather than duplicated here, since both are reusable lessons beyond the
main menu specifically.

---

## Moved from CLAUDE.md (Oct 2026)

### Menu screens (from CLAUDE.md)

Newer than the `pantheon_overlay.gd` bullet above:

- **Pantheon** → `PantheonOverlay` (Pantheon Encyclopedia) — three framed blocks (`ScaledNinePatch` like DeckOverlay): header panel (emblem slot, title, total `owned / total` across all pantheons), pantheon bar (fixed `ALL` chip + horizontally pannable row of multi-select pantheon chips; empty selection = ALL), main panel with CARD TYPE (ALL/GODS/UNITS/SPELLS) + OWNED ONLY filters over a vertical scroll of collapsible per-pantheon sections (header: logo, name, whole-pantheon `owned / total` that ignores filters, chevron; collapsed = first row of `columns` cards, expanded = all; a single remaining pantheon is auto-expanded). Tiles are `DeckCardTile` (non-draggable, progress bar), laid out by `WrapCardGrid` (`scripts/ui/wrap_card_grid.gd` — fixed columns, height from width, min width 0 so the page never spills out of MainContent); chips are `FilterChip` (`scripts/ui/filter_chip.gd` — own tap detection, swipe never toggles). Filter/expand state is session-only (in memory, not saved). A tile tap emits `card_detail_requested(id, kind)` and `main_menu.gd` opens `CardDetail`
- **Battles** (home tab, `HomeView`) → active god showcase + `BattleCard` → `PreMatchFlow` (finding → pre-match panel → arena; fills `MatchConfig`)
- Deck tiles are sized via static `DeckCardTile.width_for_height()` / `height_for_width()`; no locked slot / slot-unlock mechanic
- `DeckTile` (Pantheon) / `DeckCardTile` (Deck) change nothing themselves — they only report taps/drops; logic stays in the pages
