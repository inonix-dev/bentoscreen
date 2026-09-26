# bentoscreen 🍱

Menu-bar app for macOS: one hotkey puts every app of a layout in its slot.

- `ctrl+opt+1` **Agent**: browser top-left (2/3), chat bottom-left (1/3), Claude / Zed / iTerm2 right half
- `ctrl+opt+2` **Half / Half**: browser left, the rest right

Edit layouts from the menu (🍱 → Edit Layouts…, then Reload). Each slot is a list of apps
(name or bundle id) and a rect as fractions of the screen, `x,y` from the top-left:

```json
{ "apps": ["LINE", "Discord"], "x": 0, "y": 0.6667, "w": 0.5, "h": 0.3333 }
```

Layouts apply to the screen under the mouse. Apps that aren't running are skipped.

## Install

Unzip, move `bentoscreen.app` to /Applications, open it, and allow it under
System Settings → Privacy & Security → Accessibility. Unsigned builds: the first open needs
Privacy & Security → **Open Anyway**, and after each update remove + re-add it in Accessibility.

## Build

`./build.sh` → `build/bentoscreen.app` + `.zip` (universal, ad-hoc signed).
`SIGN_ID="Developer ID Application: …" ./build.sh` signs with a real identity.
