# BentoScreen

Menu-bar app for macOS: one hotkey puts every app of a layout in its slot.

- `ctrl+opt+1` **Agent**: browser top-left (2/3), chat bottom-left (1/3), Claude / Zed / iTerm2 right half
- `ctrl+opt+2` **Half / Half**: browser left, the rest right

Snap the focused window, ShiftIt-style — press the same key again to cycle ½ → ⅔ → ⅓:

- `ctrl+opt+cmd ←/→` left / right part, full height
- `ctrl+opt+cmd ↑/↓` top / bottom part, same column
- `ctrl+opt+cmd 1/2/3/4` top-left / top-right / bottom-left / bottom-right corner
- `ctrl+opt+cmd M` fill the screen
- `ctrl+opt+cmd C` center, same size
- `ctrl+opt+cmd N` move to the next display

Edit `~/.config/bentoscreen/layouts.json`, then menu bar icon → Reload Layouts. Each slot is a list of apps
(name or bundle id) and a rect as fractions of the screen, `x,y` from the top-left:

```json
{ "apps": ["LINE", "Discord"], "x": 0, "y": 0.6667, "w": 0.5, "h": 0.3333 }
```

Layouts apply to the screen under the mouse. Apps that aren't running are skipped.

## Install

Unzip, move `BentoScreen.app` to /Applications, open it, and allow it under
System Settings → Privacy & Security → Accessibility. Release builds are self-signed, so the
first open needs Privacy & Security → **Open Anyway**; the Accessibility grant survives updates.
To start it at login: menu bar icon → Open at Login.

## Build

`./build.sh` → `build/BentoScreen.app` + `.zip` (universal). It signs with the `BentoScreen Dev`
code-signing certificate from your keychain (create a self-signed one in Keychain Access), or
falls back to ad-hoc, which loses the Accessibility grant on every rebuild.
`SIGN_ID="Developer ID Application: …" ./build.sh` signs with another identity; `SIGN_ID=-` forces ad-hoc.

Menu bar icon: Remix Icon `layout-masonry-fill`, Apache-2.0.
