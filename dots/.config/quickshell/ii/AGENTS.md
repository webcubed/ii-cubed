# AGENTS.md — ii-eve Quickshell Dotfiles

Working guide for AI models editing this codebase. Read this before making changes.

**IMPORTANT: When you discover new patterns, conventions, or gotchas — or when new services/features are added — UPDATE THIS FILE. It is a living document. Future models depend on it being accurate and current.**

## Quick Reference

| What | Where |
|------|-------|
| Shell entry | `shell.qml` |
| Config singleton | `modules/common/Config.qml` → `Config.options.*` |
| Paths | `modules/common/Directories.qml` |
| Services | `services/*.qml` (72+ singletons) |
| Bar components | `modules/ii/bar/BarComponent.qml` + `modules/ii/bar/*.qml` |
| Component registry | `modules/common/BarComponentRegistry.qml` |
| Extensions | `services/ExtensionManager.qml`, `~/.config/illogical-impulse/extensions/` |
| Settings app | `settings.qml`, `modules/settings/` |
| Scripts | `scripts/` (bash/python, called via `Process`) |

## Architecture

```
shell.qml
  ├─ MaterialThemeLoader.reapplyTheme()
  ├─ FirstRunExperience.load()
  ├─ ConflictKiller.load()
  └─ PanelFamilyLoader ("ii" or "waffle")
       └─ IllogicalImpulseFamily.qml
            ├─ Bar.qml → BarContent.qml → BarComponent.qml (Repeater)
            ├─ SidebarPolicies (left: AI, booru, translator)
            ├─ SidebarDashboard (right: notifications, toggles, wifi, BT)
            ├─ Background, Overlay, OSD, Dock, Lock, Overview...
            └─ ...all other panels
```

## File Conventions

### Services (`services/*.qml`)

Every service is a singleton:

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common    // Config, Directories, Appearance, Translation
import qs.services          // Other services (Audio, Network, etc.)
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // Reactive config binding:
    property bool myEnabled: Config.options?.mySection?.enabled ?? false

    // Process for external commands:
    Process {
        id: myProc
        stdout: StdioCollector {
            onStreamFinished: root.handleOutput(this.text)
        }
    }

    // Fire-and-forget:
    Quickshell.execDetached(["notify-send", "title", "body"])

    // Init:
    Component.onCompleted: { /* ... */ }
}
```

**Naming**: PascalCase filename matches the singleton name. `Audio.qml` → `Audio`, `BatteryService.qml` → `BatteryService`.

### Adding a New Service

1. Create `services/MyService.qml` with the singleton pattern above.
2. Add config section in `Config.qml` if needed.
3. Touch it in `shell.qml` `Component.onCompleted` if it must initialize early.
4. Reference it anywhere as `MyService.property` (auto-imported via `qs.services`).

### Bar Components

**To add a new bar widget:**

1. Create the QML file in `modules/ii/bar/MyWidget.qml` (horizontal). Optionally create `modules/ii/verticalBar/VerticalMyWidget.qml`.

2. Register in `BarComponentRegistry.qml`:
   ```qml
   { id: "my_widget", icon: "icon_name", title: "My Widget" }
   ```

3. Add to `BarComponent.qml`:
   ```qml
   // In compMap:
   "my_widget": [myWidgetComp, myWidgetCompVert],

   // Component definitions:
   Component { id: myWidgetComp; MyWidget { vertical: rootItem.vertical } }
   Component { id: myWidgetCompVert; Vertical.MyWidget {} }
   ```

4. Optionally add default position in `Config.qml` under `bar.layouts`.

**compMap array order**: `[horizontal, vertical, expressiveHorizontal, expressiveVertical, minimalHorizontal, minimalVertical]`

### Extensions

Extensions live in `~/.config/illogical-impulse/extensions/installed/<name>/`. Each has an `extension.json`:

```json
{
  "name": "My Extension",
  "version": "1.0.0",
  "contributes": {
    "barComponents": [{ "identifier": "ext_widget", "qml": "Widget.qml" }],
    "services": [{ "id": "ext_service", "qml": "Service.qml" }],
    "overlayWidgets": [{ "identifier": "ext_overlay", "qml": "Overlay.qml" }]
  }
}
```

Extension components are loaded dynamically via `ExtensionManager.loadExtensionQmlComponent("file://" + path + "?_t=" + Date.now())`. The `?_t=` cache-buster is required.

### Config (`Config.qml`)

Config is a `FileView` + `JsonAdapter` wrapping `~/.config/illogical-impulse/config.json`.

**To add a new config section:**

```qml
// Inside the root JsonAdapter block:
property JsonObject mySection: JsonObject {
    property bool enabled: false
    property string someValue: "default"
    property int someNumber: 42
}
```

**Reference in code:**
```qml
property bool isEnabled: Config.options?.mySection?.enabled ?? false
```

**Write config:**
```qml
Config.options.mySection.enabled = true   // Auto-debounced write (75ms)
```

Config writes are debounced. The `ready` property must be true before reading.

### Scripts (`scripts/`)

Called from QML via `Process`:

```qml
Process {
    id: myProc
    command: ["python3", FileUtils.trimFileProtocol(`${Directories.scriptPath}/my_script.py`), arg1, arg2]
    stdout: StdioCollector { onStreamFinished: { /* this.text */ } }
}
```

Scripts are standalone bash/python files. Use `Quickshell.shellPath("scripts/relative/path")` to resolve paths.

## Critical Gotchas

### 1. Qt Key Handlers — Use Arrow Function Syntax

```qml
// CORRECT:
Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Escape) { /* ... */ }
    event.accepted = true
}

// WRONG — will silently fail:
Keys.onPressed: {
    if (key === Qt.Key_Escape) { ... }  // `key` undefined
}
```

### 2. Animation Leaks — Never Use Inline NumberAnimation

Shared animation objects leak when triggered rapidly. Always create fresh instances:

```qml
// WRONG — shared object, causes visual glitches:
Behavior on x { NumberAnimation { duration: 200 } }

// CORRECT — fresh instance per trigger:
Behavior on x {
    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
}
```

### 3. Layout.fillWidth in ListView/Repeater Delegates

Does not work — delegates have no fixed parent width to fill:

```qml
// WRONG in a ListView delegate:
Item { Layout.fillWidth: true }

// CORRECT:
Item { width: listView.width }
```

### 4. MouseArea in ColumnLayout Eats Events

A MouseArea inside a ColumnLayout captures all mouse events, blocking siblings:

```qml
// FIX: propagate events
MouseArea {
    acceptedButtons: Qt.NoButton
    propagateComposedEvents: true
    onClicked: (mouse) => mouse.accepted = false
}
```

For click handlers, use `Qt.PointingHandCursor` and wrap in an `Item` with `Layout.preferredHeight`:

```qml
Item {
    Layout.preferredHeight: headerRow.implicitHeight
    RowLayout { id: headerRow; /* content */ }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { /* action */ }
    }
}
```

### 5. Property Name Conflicts

Do not shadow QML built-in properties. `Item` has `enabled`, `visible`, `width`, `height`, `children`, etc.

```qml
// WRONG — overrides Item.enabled:
readonly property bool enabled: Config.options?.foo?.bar ?? false

// CORRECT — use a unique name:
readonly property bool myFeatureEnabled: Config.options?.foo?.bar ?? false
```

### 6. Rectangle Does Not Have topRadius/bottomRadius

```qml
// WRONG:
Rectangle { topRadius: 10; bottomRadius: 5 }

// CORRECT — use uniform radius:
Rectangle { radius: 10 }
// Or use a custom Shape for asymmetric corners.
```

### 7. Singleton Lazy Loading

Singletons load on first reference. To force early init, touch a property in `shell.qml`:

```qml
Component.onCompleted: {
    PolkitService.agent  // Forces load
}
```

### 8. Config Read Timing

Do not read `Config.options.*` before `Config.ready === true`. Guard with:

```qml
readonly property bool myValue: Config.ready ? Config.options?.mySection?.value ?? false : false
```

`Weather` is the worked example of getting this wrong: it used to fetch in `Component.onCompleted`, i.e. with the default provider and an empty city, and that request's failure is what popped "weather service unreachable" at login. It now waits for `Config.ready` (a `Connections` on `onReadyChanged`), its fetch scripts print `failMarkerNetwork` / `failMarkerCity` on stdout instead of signalling failure with empty output, `_handleFetchFailure()` retries three times with a growing delay before it notifies, and the refresh timer runs even with GPS on so the city fallback keeps working when no position fix ever arrives.

### 9. Import Paths

Modules resolve from directory structure automatically (no `qmldir` files). Import `qs.modules.ii.bar` to access types in `modules/ii/bar/`.

Sub-subdirectories (like `modules/ii/bar/cards/`) are imported by their parent:
```qml
import "../cards"   // from modules/ii/bar/weather/WeatherPopup.qml
import "./cards"    // from modules/ii/bar/BatteryPopup.qml
```

### 10. Reuse Process for Sequential Operations

Store pending context as properties, not closures:

```qml
Process {
    id: proc
    property string _pendingId: ""
    onExited: (code, _) => { handleResult(_pendingId) }
}
proc._pendingId = "item-1"
proc.exec(["cmd", args])
```

### 11. Background Widget Culling

Background widgets (`modules/ii/background/widgets/`) are always loaded when enabled. To reduce GPU/CPU usage, use the cull-on-occlude feature:

- **Config**: `Config.options.background.widgets.cullWhenOccluded` (bool)
- **State**: cull fires only on `GlobalStates.widgetsHidden` (`screenLocked ||
  fullscreenActive`) — the states where widgets are actually invisible.
  Transient overlays (search, overview, launcher, OSK, …) leave widgets
  visible, so they must NOT cull (user report: search-key culling was wrong).
  `GlobalStates.widgetsOccluded` (the overlay list) still drives
  `widgetsVisible`/polling gates — don't cull from it.
- When cull is enabled, `FadeLoader.shown` bindings in `Background.qml` add `&& !bgRoot.widgetsOccluded` (backed by `widgetsHidden`)
- `AbstractBackgroundWidget.qml` opacity also checks this, so even extension-loaded widgets are culled
- Culled **bar** groups also hide: `BarComponent` wrapper `visible: itemLoader.active` — otherwise the empty `BarGroup` pill stays on screen (the "empty pills" artifact; Row skips invisible children, so the layout reflows cleanly)

### 12. Background Widget Grid Placement

Widgets can be snapped to a grid instead of free-positioned:

- **Config**:
  - `Config.options.background.widgets.grid.enabled` (bool)
  - `Config.options.background.widgets.grid.columns` (int, default 6)
  - `Config.options.background.widgets.grid.rows` (int, default 4)
- Each widget config entry also has `gridColumn` and `gridRow` for initial placement
- When grid is enabled and widgets are unlocked, a grid overlay (dashed white lines) appears while dragging widgets
- The grid overlay is drawn on a `Canvas` inside `WidgetCanvas` with `z: 100` to render above widgets
- A `Connections` handler on `bgRoot.draggingWidget` triggers immediate repaint when dragging starts/ends
- A polling `Timer` (200ms) keeps the overlay repainted while visible
- Widget hitbox (cell highlight) appears at the current drag position
- **Now enabled**: config has `cullWhenOccluded: true`. Additionally, bar
  widgets that tick every second (`BarComponent.liveUpdateIds`: clock, date,
  system_monitor, network_speed, music_player, timer) unload entirely while
  `GlobalStates.fullscreenActive` — focused window is in TRUE fullscreen
  (hyprctl `fullscreen === 2`; `1` = maximized never culls: maximized
  windows respect the bar's exclusive zone, the bar stays visible).
- When grid is enabled, widgets snap to grid cells on release
- `AbstractBackgroundWidget.qml` computes `gridCellWidth`/`gridCellHeight` from `scaledScreenWidth`/`scaledScreenHeight`
- Grid position is saved back to config (`configEntry.gridColumn`/`gridRow`) on drag release

### 13. AI Attachments Go Through `scripts/ai/attach.py`

Every file the AI panel touches runs `python3 scripts/ai/attach.py <cmd>`:
`probe <path>` (metadata JSON), `extract <path>` (text JSON), `inject <body> <spec>`
(write base64/text/extract into the request body at `@@II_ATT_n@@` markers),
`search <rootsJson> <query> <limit> <kindsJson>`, `peek <path> <maxChars>`.
If this file is missing, stdout is empty, `JSON.parse` throws in `Ai.qml`, and
every attach fails with "Could not read that file." — **always print JSON on
stdout for probe/extract/search/peek** (errors as `{"error": ...}`, `inject`
exits non-zero with a plain message instead).

Screen snip → attach chain: `AiChat` emits `GlobalStates.snipForAiRequested()`
→ `RegionSelector.askAI()` sets `action = AskAI` and opens → `RegionSelection.snip()`
pipes the crop to `wl-copy` and calls `Ai.handleClipboardAndAttach()` → cliphist
entry decoded → `Ai.attachFile()`. `GlobalStates` carries signals, not just
booleans — cross-component requests go through it.

Snip → annotate chain (built-in editor): entry via `SnipAction.Edit` (toolbar
`draw` toggle in `OptionsToolbar`, RMB during a Copy snip, ipc `region annotate`,
or GlobalShortcut `regionAnnotate`) → `RegionSelection.cropForAnnotation()`
**copies the FULL screen capture** (`cp` — not a crop) to
`screenshotTemp/annotate-<ts>.png` and emits
`annotationReady(path, screen, region)` with the selected rect in image
(physical) px → `RegionSelector` sets path/screen/`annotateRegion`, dismisses
the selector first, and opens `AnnotationEditor` on the next tick
(`Qt.callLater`) — layer-shell surfaces must never coexist (same reason as
Translate). The editor seeds a draggable `crop` (image px, `initCrop()` on
image Ready + region change + visible) shown as a `cropOverlay` **sibling of
`view`** (never a child — `grabToImage` must not bake the chrome in): dim
rects outside the crop, border, 8 handles (4 corners + 4 sides, min 80 image
px). Tools: pen/highlight/arrow/line/dash/dot/rect/ellipse/triangle/text on a
`Canvas`; export (`withExported`) grabs the whole view, then a reused Process
magick-crops it to `crop` **via `exportCrop()` + `cropScript`**: the rect is
clamped to the capture and rounded (a negative/NaN/out-of-bounds rect makes
`magick -crop` exit non-zero), and the crop is skipped when it ≈ the full
image. The grab is device px while `crop` is image px, so `cropScript` lets
ImageMagick measure the grab (`identify`, awk scaling) instead of dividing by
`result.image.width` — that path produced `NaN` geometry on HiDPI/mismatched
dpr and, because the old `onExited` dismissed on any non-zero exit, the whole
export died silently and the clipboard kept the *previous* (unannotated) image.
A failed crop now falls back to the uncropped annotated grab (stderr is logged)
rather than throwing the snip away. `doCopy`/`doSave`/`doExternal` all go
through it, so the external editor (satty via `useSatty ? satty : swappy`)
receives the cropped, annotated result. RMB→Edit
no longer remaps Edit→Copy on LMB: only `Copy + RMB` flips to Edit.
Drop-ups: `property string openMenu` (`"" | "shape" | "arrow"`) drives ONE
full-screen `menuHost` (z:11) that owns both menus + its close-backdrop —
menus overflow the toolbar Row, and QML hit-testing only descends into items
whose ANCESTORS contain the point, so a menu parented under the toolbar is
unclickable (learned the hard way). `shapeList` = rect/ellipse/triangle
(ellipse drawn as 4 beziers — Qt Canvas has no `ctx.ellipse`); `lineList` =
arrow/line/dashed/dotted (dashes via `ctx.setLineDash`, reset after).
Per-session reset: `resetState()` runs on `visible` AND `imagePath` change,
clears shapes/draft/openMenu/crop, and MUST call `canvas.requestPaint()` —
the Canvas bitmap survives hide/show, so without the repaint the previous
snip's drawings stay on screen over the new capture.

### 14. ToolbarTabBar Sizes Unstretched Toolbars via `implicitWidth`

`ToolbarTabBar.implicitWidth` must stay `contentItem.implicitWidth` (natural
tab width), never `0`: `Toolbar` derives its pill width from
`toolbarLayout.implicitWidth`, so a 0 collapses the pill in toolbars that are
NOT externally stretched (region selector Row, cheatsheet) — the tab Flickable
gets ~0 width (tabs invisible) and the unclipped `activeIndicator` spills over
neighboring buttons (e.g. the selector's close Fab). Stretched contexts (sidebar
`Layout.fillWidth`) are driven by the parent layout and unaffected by this
value. If tabs look clipped or a phantom pill appears behind a neighbor, check
this first.

### 15. Hyprland Events Are Native — No socat Needed

`Connections { target: Hyprland; function onRawEvent(event) {...} }` streams
socket2 events as `event.name`/`event.data` (precedent: `Brightness.qml`).
`GlobalStates.fullscreenActive` = the FOCUSED window is in TRUE fullscreen —
hyprctl `activewindow`'s `fullscreen` field is an enum (`0` none, `1` MAXIMIZED,
`2` FULLSCREEN, `FullscreenTypes.hpp`); only `2` culls, because maximized
windows still leave the bar visible (exclusive zone). A maximized window can
be active without the user maximizing it (e.g. kitty swallowing a maximized
window), which is why culling on `> 0` culled the bar on every terminal open —
but event-driven inference alone also went stale (culling visible widgets until
user forced a focus event), so detection is self-verifying:
`fullscreen`/`activewindow`/`activewindowv2`/`workspace`/`workspacev2`
events restart a 150 ms debounce → `requestFullscreenSync()` → queued
`fsSyncProc.exec(["hyprctl","activewindow","-j"])` (queue flag if the
process is running — failures leave the flag as-is, fail-open toward
SHOWING widgets), plus a 2 s heartbeat `Timer` that only runs while the flag
is `true` (stale-true can't outlive 2 s; zero forks when false), plus the
startup sync. Per-second work is gated on it:
`ResourceUsage.pollingVisible` (bar open + not locked + not fullscreen, or the
background resources widget visible, or dashboard open),
`WorldClock.widgetVisible` (enable flag + `widgetsVisible` + not fullscreen),
and `BarComponent.cullLiveUpdates`. `DateTime`'s uptime timer runs at 60 s
with `triggeredOnStart` — never tie it to `resources.updateInterval`.
ResourceUsage merges its temp+GPU probes into one `hwProbeProc` fork.

### 16. A Service Reference Without `import qs.services` Sticks Panels Open

Referencing a service singleton from a file that lacks `import qs.services` throws
`ReferenceError: X is not defined` at binding evaluation, and the property keeps its
**default value** — never the computed one. `PanelLoader.extraCondition` defaults to
`true`, so a service-gated overlay builds and stays forever, ignoring config:

```qml
// IllogicalImpulseFamily.qml — without `import qs.services` this threw and the
// intrusive bedtime modal showed permanently even with bedtime disabled:
PanelLoader { extraCondition: BedtimeService.intrusiveDue; component: BedtimeOverlay {} }
```

Fix: add `import qs.services` to the file (checked for `ScreenTimeLimits` too).
Symptom check: `grep ReferenceError <log.qslog>` and `hyprctl layers | grep <namespace>`.

## Module Import Reference

```
qs                          → Root ii/ directory
qs.services                 → services/
qs.modules.common           → modules/common/
qs.modules.common.widgets   → modules/common/widgets/
qs.modules.common.functions → modules/common/functions/
qs.modules.ii.bar           → modules/ii/bar/
qs.modules.ii.bar.weather   → modules/ii/bar/weather/
qs.modules.ii.bar.dynamicIsland → modules/ii/bar/dynamicIsland/
qs.modules.ii.sidebarDashboard  → modules/ii/sidebarDashboard/
qs.modules.ii.sidebarPolicies   → modules/ii/sidebarPolicies/
qs.modules.ii.verticalBar   → modules/ii/verticalBar/
qs.modules.ii.background    → modules/ii/background/
qs.modules.ii.overlay       → modules/ii/overlay/
qs.modules.ii.dock          → modules/ii/dock/
qs.modules.ii.overview      → modules/ii/overview/
qs.modules.ii.lock          → modules/ii/lock/
qs.modules.ii.wallpaperSelector → modules/ii/wallpaperSelector/
```

## Key Services Cheat Sheet

| Service | Purpose |
|---------|---------|
| `Config` | Read/write `config.json` |
| `Persistent` | Read/write `states.json` (runtime state) |
| `Appearance` | Colors, fonts, rounding, animations, sizing |
| `Directories` | All filesystem paths |
| `Translation` | i18n via JSON locale files |
| `GlobalStates` | Panel open/close booleans |
| `GlobalFocusGrab` | Click-outside-to-close via Hyprland |
| `BarComponentRegistry` | Available bar components |
| `ExtensionManager` | Extension lifecycle |
| `Notifications` | Notification storage + popup |
| `Audio` | PipeWire volume control |
| `Network` | nmcli wifi/ethernet |
| `BluetoothStatus` | Bluetooth adapter + device state |
| `Battery` | UPower battery info |
| `HyprlandData` | Hyprland IPC window/monitor data |
| `MprisController` | Media player control |
| `Weather` | Weather data (wttr.in / open-meteo) |
| `Cliphist` | Clipboard history |
| `TrayService` | System tray items for the bar and lock screen. Collapses duplicate StatusNotifierItem registrations (`uniqueItems`, newest kept) because Quickshell never drops old ones and fcitx re-registers on every reload — that used to stack a keyboard icon per reload. |
| `LauncherSearch` | Search results (apps, math, commands, web) |
| `AppSearch` | Desktop entry search |
| `TailscaleService` | Tailscale VPN management (connect/disconnect, exit nodes, peers) |
| `DockerService` | Docker container management (start/stop/restart, events, memory) |
| `VpnService` | Multi-provider VPN (NetworkManager, NordVPN, ProtonVPN) |
| `EmailService` | Gmail OAuth integration (sync, send, mark read, trash) |
| `NotesService` | File-based JSON notes (add/update/delete) |
| `TimerService` | Pomodoro cycles, persisted stopwatch (laps via `stopwatchRecordLap()`), and standalone countdown timer (`countdownSet(minutes)`, `countdownToggle()`, `countdownReset()`) |
| `CalendarService` | khal/CalDAV calendar integration (Google Calendar via vdirsyncer). Events loaded via `khal list --json`. Provides `getTasksByDate(date)` and `addItem(item)`/`removeItem(item)`. |
| `Todo` | File-based todo list (`todo.json`). Supports optional `deadline` field for calendar integration. `addTask(desc, deadline)`, `getTasksWithDeadline(date)`. |
| `Authenticator` | TOTP codes in the launcher (`!` prefix by default). Streams codes from `scripts/authenticator/otp.py`; `/auth` commands add/remove/import/export. Store: `~/.config/illogical-impulse/authenticators.json`. See "Authenticator (TOTP Codes)". |
| `Dictionary` | Word lookups for `d <word>` through dictionaryapi.dev (curl). Parsed entries, synonyms, examples and links. |
| `UrbanDictionary` | Slang lookups for `ud <term>` through Urban Dictionary's JSON endpoint (curl). |
| `TranslationService` | Translations for `t <text>` (MyMemory, no key) with tone-marked pinyin from zhconvert for the Chinese side. Not named `Translate`: that is a QtQuick built-in type. |
| `LauncherMenu` | Shared launcher menu helpers: `copy`, `openUrl`, `backRow`, `noteRow`, `partOfSpeechIcon`, `parseWordQuery`. |
| `AuthMenu` / `DictionaryMenu` / `UrbanMenu` / `TranslationMenu` / `CommandPalette` | One module per launcher surface, each building descriptor rows plus its submenu drill targets. |

## Google Calendar Integration

Calendar events sync via **vdirsyncer** → **khal** → **CalendarService**.

**Setup:**
1. `uv tool install vdirsyncer khal` (or `sudo pacman -S vdirsyncer khal`)
2. Configure `~/.config/vdirsyncer/config` with Google OAuth credentials
3. Run `vdirsyncer discover` (opens browser for auth)
4. Run `vdirsyncer sync` to pull events
5. Configure `~/.config/khal/config` with calendar paths

**Config files:**
- `~/.config/vdirsyncer/config` — vdirsyncer pairing config (Google ↔ local ICS)
- `~/.config/khal/config` — khal calendar discovery config
- `~/.vdirsyncer/google_token` — OAuth token (auto-generated)

**Auto-sync (opt-in):** `Config.options.calendar.sync.enable` defaults to `false`. When on, ii runs the sync itself; `onStartup`, `intervalMinutes` (0 turns the timer off) and `command` (run through `bash -lc`) control it. A cron entry is no longer needed. The settings page shows the last sync time or error and has a "Sync now" button, which works even with automatic sync off.

**Calendars:** `Config.options.calendar.disabledCalendars` lists names from `khal printcalendars` that ii ignores; the settings page lists every khal calendar and toggles them one by one. Disabled names are passed to khal as repeated `--exclude-calendar` args, so the query never fetches them; a toggle re-runs the query. khal does not take calendar names positionally, so filtering cannot happen there.

**New Google calendars:** `collections = ["from a"]` in the vdirsyncer config syncs whatever exists remotely, but khal only reads calendars that have their own `[[name]]` block. After creating a calendar in Google: `vdirsyncer discover google_calendars`, then `vdirsyncer sync`, then add a `[[name]]` block to `~/.config/khal/config` and reload the shell.

**Binary paths:** `Config.options.calendar.khalPath` defaults to empty, which looks khal up on the login shell's PATH and then falls back to `~/.local/bin/khal`. The sync command is a plain string, so a full path (or `uv tool run vdirsyncer sync`) works when PATH does not have it.

**Gotcha:** CalendarService uses `dd.MM.yyyy` date format for khal. The khal `longdateformat` must match.

## Authenticator (TOTP Codes)

QML has no crypto, so codes come from a Python backend that streams one JSON
line per second; the shell only formats and copies them.

| What | Where |
|------|-------|
| Service | `services/Authenticator.qml` |
| Backend | `scripts/authenticator/otp.py` (`stream`, `code`, `list`, `add`, `update`, `remove`, `import`, `export`) |
| Store | `Directories.authenticatorsPath` → `~/.config/illogical-impulse/authenticators.json` (0600, hand-editable, bare JSON array also accepted) |
| Launcher prefix | `Config.options.search.prefix.authenticator` (default `!`) |
| Options | `Config.options.search.authenticator.{enable,digits,period,algorithm,clearClipboardAfter}` |

- Launcher results are created in `LauncherSearch.qml`'s authenticator-prefix
  branch with `liveAuthenticatorId`; `SearchItem.qml` renders the live code chip
  and countdown itself. Do **not** bake the code into `name` — a result-list
  rebuild on every tick would reset the selection.
- The stream only runs while `GlobalStates.overviewOpen || searchOpen` and
  services exist (`streamWanted`), with a retry timer plus a 10s watchdog.
- `copyCode()` copies immediately from the stream; if codes are not ready yet it
  falls back to a one-shot `otp.py code <id>` process.
- Import accepts own-store JSON, Aegis, andOTP, 2FAS, generic JSON entries with a
  secret, and `otpauth://` URI lists (file path or clipboard). Google
  Authenticator `otpauth-migration://` links are rejected with a message.
- Export writes JSON or `otpauth://` URIs (0600); the path goes to the clipboard.
- Store writes are atomic (temp file + `os.replace`) so `FileView.watchChanges`
  never sees a half-written file.

Search-bar commands (`/auth …`, action prefix): `add <Issuer:account> <secret>`,
`remove`, `rename`, `secret`, `set <label> key=value…`, `import [file]`,
`export [json|uri] [file]`, `list`, `help`.

## Launcher Menus, Lookups and Subcommands

Search-bar surfaces are menus, not notifications. A row carries `drillQuery`
when activating it should navigate (Flow Launcher style) instead of executing:
`SearchItem.onClicked` then emits `navigate`, and `SearchWidget.setSearchingText()`
applies it, so submenus are just query text and backspace/Escape walk back out.

| Surface | Shape |
|---------|-------|
| `!` auth | services → `!<label> >` service menu (code, upcoming codes, secret, details, rename, change secret, delete) → `!<label> > rename ` / `secret ` text pages |
| `d <word>` | definitions; `!d` definitions, `!s` synonyms/antonyms, `!e` examples, `!` links (Flow.Launcher.Dictionary format). `d <word> > <meaning>.<index>` is a definition page |
| `ud <term>` | Urban Dictionary definitions; `!e` examples, `!` links. `ud <term> > <index>` is an entry page |
| `t <text>` | Translate: English goes to Chinese, anything else goes to English, with tone-marked pinyin for whichever side is Chinese. `t en>fr <text>` / `t >ja <text>` picks the languages explicitly. `t <text> >` is the detail page |
| `/` | command palette: every action with icon + description, drilling to `/cmd `; `/auth` lists its subcommands with argument skeletons |

- Prefixes live in `Config.options.search.prefix` (`dictionary: "d"`, `urban: "ud"`,
  `translation: "t"`).
  Word prefixes only count when followed by a space — plain typing must not be
  hijacked — hence `LauncherSearch._wordPrefixQuery()` and
  `SearchBar.isWordPrefix()`.
- One module per surface: `AuthMenu`, `DictionaryMenu`, `UrbanMenu`,
  `TranslationMenu` and `CommandPalette`, each exposing `rows(...)`.
  `LauncherMenu` only holds the shared helpers (`copy`, `openUrl`, `backRow`,
  `noteRow`, `partOfSpeechIcon`, `parseWordQuery`). None of them takes an
  action-prefix parameter it does not use.
- They return plain descriptor objects
  (`{type, name, verb, icon, iconType, fontType, maxLines,
  liveAuthenticatorId, liveUpcomingIndex, drill, execute, actions}`);
  `LauncherSearch._resultFromDescriptor()` turns them into
  `LauncherSearchResult`s. Keep widget imports out of them.
- **Never build rows from a value that changes on a timer.** Reading
  `Authenticator.codes` in a menu rebuilt the results list every second and the
  selection jumped back to the top while scrolling. Upcoming-code rows carry
  only `liveAuthenticatorId` + `liveUpcomingIndex`; `SearchItem` reads the code
  and countdown in the delegate (`displayNameText` / `displayTypeText`), and
  the copy closures resolve the code when activated, not when built.
- `/auth` validates while you type and only runs a valid action, so bad syntax
  never needs a notification: rows show "No service matches", "That secret
  isn't base32", etc. Copying a code is silent, and add/remove/rename no longer
  toast on success (import/export still report their outcome).
- Definitions need multiple lines: `LauncherSearchResult.maxLines` drives
  `SearchItem`'s wrap/maximumLineCount. Long type lines are elided so the verb
  and action buttons never get pushed off the row.
- `Config.options.search.prefix` defaults do **not** reach an existing
  `~/.config/illogical-impulse/config.json`: the saved object wins, so a new
  prefix key must be added to that file too (otherwise the shell sees it as
  `undefined` and the prefix silently falls through to normal search).
- Never name a singleton after a QtQuick type. `Translate.qml` made the whole
  shell fail to reload with `Composite Singleton Type Translate is not
  creatable`, because QML already has a `Translate` transform — hence
  `TranslationService`.

## Translation and Pinyin

`TranslationService.qml` parses the query first: `parse()` strips an optional
`<from>><to>` language spec and a trailing `>` detail marker. Without a spec the
direction is guessed (`looksEnglish()`: Han/kana/hangul or accented Latin →
English, otherwise → 中文), so English goes to Chinese and everything else goes
to English. Explicit pairs go straight to MyMemory's `langpair`, source may be
empty (`>ja` = Autodetect). It then asks zhconvert's `Pinyin` converter for the
Chinese side. zhconvert answers in numbered tones
(`ni3 hao3`); `numberedToToneMarks()` converts them to diacritics
(`nǐ hǎo`) — Google's `translate_a` endpoint is not reachable from this network
("automated queries" page), so it is not used. Pinyin is shown as its own row on
the result and detail pages, and follows `pinyinOf` (`source` or `translation`).

Language codes are normalised in `normaliseLanguage()` (`zh`/`cn`/`chinese` →
`zh-CN`, `jp` → `ja`, …) and listed in `languageNames`; unknown codes fall back
to the guessed direction rather than erroring. `directionLabel()` renders the
"English → Français" type line, `detectedSource` keeps MyMemory's detected
language so the detail page can offer the reverse translation.

## Sidebar Pages (Left Sidebar Tabs)

The left sidebar (`SidebarPoliciesContent.qml`) has tabs controlled by config flags:

| Tab | Config Flag | Icon | Component |
|-----|-------------|------|-----------|
| AI | `Config.options.policies.ai !== 0` | `neurology` | `AiChat.qml` |
| Translator | `Config.options.policies.translator !== 0` | `translate` | `Translator.qml` |
| Media | `Config.options.policies.player !== 0` | `music_note` | `SidebarPlayerControl.qml` |
| Wallpapers | `Config.options.policies.wallpapers !== 0` | `wallpaper` | `WallpaperBrowserUI.qml` |
| Anime | `Config.options.policies.weeb !== 0` | `bookmark_heart` | `Anime.qml` |
| Tailscale | `Config.options.policies.tailscale !== 0` | `hub` | `TailscalePage.qml` |
| Docker | `Config.options.policies.docker !== 0` | `inventory` | `DockerPage.qml` |
| VPN | `Config.options.policies.vpn !== 0` | `shield` | `VpnPage.qml` |
| Email | `Config.options.policies.email !== 0` | `mail` | `EmailPage.qml` |
| Notes | `Config.options.policies.notes !== 0` | `sticky_note_2` | `NotesPage.qml` |
| Phone | `Config.options.policies.phone !== 0` | `smartphone` | `phone/Phone.qml` |
| Extensions | Dynamic | Dynamic | Extension-provided |

**Sidebar navigation:**
- `Ctrl+Tab` / `Ctrl+Shift+Tab` — next/prev tab
- `Ctrl+PageDown` / `Ctrl+PageUp` — alternative next/prev
- Tab / Shift+Tab — next/prev (no modifier, when no text input focused or input is empty)
- Left / Right arrows — prev/next tab (same conditions)

**Tab label display:** `maxTextTabs` on `ToolbarTabBar` controls when tabs switch from icon+text to icon-only. Default: 3 (collapsed) / 4 (extended sidebar).

To add a new sidebar tab:
1. Create `modules/ii/sidebarPolicies/MyPage.qml`
2. Add `property bool myPageEnabled: Config.ready && (Config.options.mySection?.enabled ?? false)` to `SidebarPoliciesContent.qml`
3. Add entry to `tabButtonList` array
4. Add `Component { id: myPage; MyPage {} }` block
5. Add to `contentChildren` array

## Cheatsheet Tabs

The cheatsheet (`modules/ii/cheatsheet/Cheatsheet.qml`) has built-in tabs plus extension-contributed tabs.

**Built-in tabs:**
| Tab | Icon | Component |
|-----|------|-----------|
| Commands | `terminal` | `commands/CheatsheetCommands.qml` — saved shell commands with their forms |
| Timetable | `calendar_month` | `CheatsheetTimetable.qml` — weekly timetable from khal events with time slots, current time indicator, auto-scroll |
| Periodic table | `science` | `CheatsheetPeriodicTable.qml` + `ElementTile.qml` — AP Chem reference: Pauling electronegativity, radius, first ionization energy, STP phase, oxidation states (common ones filled) and noble-gas/full electron configurations per element, from the `details` map in `periodic_table.js` |
| Keybinds | `keyboard` | `CheatsheetKeybinds.qml` + `CheatsheetKeybindsCategory.qml` + `KeybindEditDialog.qml` + `KeybindAddNewLine.qml` — searchable, editable Hyprland keybinds (ported from the `ii-eve-cheatsheet-keybinds` extension so local fixes live in the repo; the extension's tab is deduped by identifier `keybinds`). Uses `HyprlandKeybinds`, `KeybindsEditor`, `CheatsheetSearch` and `scripts/keybinds/keybind_edit.py`, all in-repo |

**Extension tabs:** Contributions via `ExtensionManager.getContributionPoint("cheatsheet")`.

To add a built-in tab:
1. Create `modules/ii/cheatsheet/MyTab.qml`
2. Add a `Component { id: myTabComponent; MyTab {} }` in `Cheatsheet.qml`
3. Add to `builtInTabs` array: `{ key: "mytab", icon: "icon_name", name: Translation.tr("Tab Name"), component: myTabComponent }`

**Arrow key navigation in cheatsheet:**
- Left/Right arrows: switch tabs (fallback only — a page that publishes `handleKey(event)` gets them first)
- Ctrl+Tab / Ctrl+Shift+Tab (Key_Backtab) or PageDown/PageUp: switch tabs (works everywhere, including pages that eat the arrows)
- Esc: close cheatsheet
- **Keys reach the page through the background.** A tab button usually owns the active focus, so a page's own `Keys.onPressed` does not fire. `cheatsheetBackground` therefore calls `page.handleKey(event)` on the current page before its own tab shortcuts, and the Periodic table implements it (arrows walk the grid via the spatial pick in `moveSelection()`, typing filters, Enter picks, Backspace edits, first Esc clears the query and returns false so the sheet can close). Pages without `handleKey` keep the old arrow behaviour.
- Modifier checks must test bits (`event.modifiers & Qt.ControlModifier`), never compare the whole value: Ctrl+Shift+Tab carries Shift, which made the old `modifiers === Qt.ControlModifier` branch drop it.
- Periodic table tiles are `focusPolicy: Qt.NoFocus` so a click cannot take keyboard focus.
- Because nothing reliably holds focus, the arrows are ALSO wired as `Shortcut { sequence: "Up" … }` gated on `root.isCurrentPage` (`tabIndex` vs `Persistent.states.cheatsheet.tabIndex`). Shortcuts are matched by the window before key delivery, so they work no matter who owns focus — that is what finally made up/down work. Don't drop them in favour of the Keys handler.
- Layers: `c` category, `e` electronegativity, `r` radius, `i` ionization energy, `b` block, `p` phase. A layer recolours tiles (`trendColor()`) and replaces the name with the value (`tileLabel()`); numeric layers render a gradient legend from min/max of the real data.
- **Search bar.** The page owns `query`; the `ToolbarTextField` in the table header mirrors it with a `Binding { property: "text"; restoreMode: Binding.RestoreNone }` and writes back in `onTextChanged`, so typed text is always on screen and typing in the bar filters too. `/` focuses the bar — required because `c e r i b p` are layer keys, so "carbon" could never start a search otherwise. Layer keys fire only while `query` is empty **and** the bar is unfocused.
- Escape inside the bar is its own `Shortcut { sequence: "Escape"; enabled: root.isCurrentPage && searchField.activeFocus }`, not the page's `handleKey`: window shortcuts are matched before key delivery, so the bar clears (then `root.forceActiveFocus()` hands the keyboard back) without racing the TextField's own key handling. The other Escape shortcuts in the tree are gated to the Commands tab/form, so there is no ambiguity.
- **Element colours** live in `palette.js` (Catppuccin Macchiato), imported as `Mac`: importing it as `Palette` shadows QtQuick's own `Palette` type and qmllint reports the colours as missing on `QQuickPalette`. Only entries something reads are kept.
- **Tile glyph contrast is measured, not guessed.** `ElementTile` paints an opaque fill — `ColorUtils.mix(accent, Appearance.colors.colLayer0, tint)` — so the colour under the glyphs is known, then picks between the accent and Macchiato `crust` by WCAG contrast ratio. At the block/phase fill (`fillStrength: 0.42`, i.e. 58% accent) the measured winner is `crust`, so gas/liquid/solid and every block get dark glyphs; numeric (0.70) and category (0.86) tiles keep the accent glyph, still ≥3.1:1. Caveat: with shell transparency enabled the wallpaper shifts the real backdrop, so `colLayer0` is an approximation there.
- **Cheatsheet sizing**: `cheatsheetBackground.height` and `cheatsheetColumnLayout.height` are clamped to the screen, so pages with tall content get a shorter viewport. A page that can overflow must put its content in a `StyledFlickable` with `contentHeight` from the content (periodic table and keybinds both do); the periodic page also scrolls the selected row into view via `ensureSelectionVisible()`.

## Bottom Widget Group Navigation

The bottom widget group (`modules/ii/sidebarDashboard/BottomWidgetGroup.qml`) has three tabs: Calendar (0), Todo (1), Timer (2).

**Keyboard navigation:**
- **Up/Down arrows:** switch between Calendar/Todo/Timer tabs
- **Left/Right arrows:** when on Timer tab, switch between Pomodoro/Stopwatch/Countdown sub-tabs
- **Ctrl+PageDown/PageUp:** switch main tabs (legacy)

## Testing Changes

## Testing Changes

Quickshell hot-reloads on file changes. To test manually:

```bash
# Start shell (kills existing instance first):
qs -p ~/.config/quickshell/ii &

# Check for errors:
qs -p ~/.config/quickshell/ii 2>&1 | grep ERROR

# The shell logs to: /run/user/1000/quickshell/by-id/<id>/log.qslog
```

Configuration loads on startup. If the shell fails to start, the error chain shows exactly which file and line has the problem.

## Git Workflow

The git repo is at `/home/webcubed/Projects/ii-eve/`, synced to `~/.config/quickshell/ii/`. The local branch is typically 30+ commits ahead of `upstream/main` (`github.com/djOB2EOTWQW1/ii-eve`).

Always check `git status` and `git diff` before committing. Never commit secrets or API keys.

## Updating This File

## Hermes Agent (AI Coding Assistant)

Installed at `/home/webcubed/.hermes/hermes-agent/` (v0.20.4). Config at `/home/webcubed/.hermes/config.yaml`.

**Providers configured:**
- **Google Gemini** (default): `gemini-2.5-flash` via `GOOGLE_API_KEY` in `.env`
- **Groq** (STT + fallback): `whisper-large-v3-turbo` for STT, `llama-3.3-70b-versatile` for chat
- **Cerebras** (fast fallback): `gpt-oss-120b` via `CEREBRAS_API_KEY` in `.env`

**Model aliases:**
| Alias | Model | Provider | Limits (free) |
|-------|-------|----------|---------------|
| `flash` | gemini-2.5-flash | Gemini | 1,500 req/day |
| `pro` | gemini-2.5-pro | Gemini | 50 req/day |
| `llama` | llama-3.3-70b-versatile | Groq | 1,000 req/day |
| `cerebras` | gpt-oss-120b | Cerebras | 1M tokens/day, 5 RPM |
| `gpt-oss` | openai/gpt-oss-120b | Groq | 1,000 req/day |

**Usage:**
- Start interactive chat: `hermes chat`
- Switch model: `hermes model` or `/model flash` in chat
- Working directory: `~` (home directory)

---

**This file is a living document.** Every model that works on this codebase should update it when:

- **New services** are added → add them to the Key Services table
- **New gotchas** are discovered → add them to Critical Gotchas
- **New patterns** are used → document them in the relevant section
- **New config sections** are added → list them in the Config section
- **New module paths** are used → add them to Module Import Reference
- **Files move** → update the Quick Reference table

Format: append to the relevant section, or create a new section if nothing fits. Keep entries concise — one line per item with a code example if helpful.
