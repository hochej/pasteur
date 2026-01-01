
## Project Overview

Pasteur is a macOS menu bar application for instant molecular structure visualization from clipboard content. Users copy molecule text (PDB/mmCIF/XYZ/MOL/SDF/MOL2) and press a global hotkey to render it in a floating viewer panel.

## Tech Stack

- **macOS Shell**: Swift + AppKit (NSStatusItem menu bar, NSPanel viewer, WKWebView)
- **Viewer Frontend**: TypeScript + Vite + Molstar (bundled locally, no CDN)
- **Package Manager**: bun for web dependencies

## Repository Structure

```
pasteur/
├── macos/                    # Swift/AppKit application
│   ├── Pasteur.xcodeproj
│   └── Pasteur/
│       ├── AppDelegate.swift
│       ├── StatusItemController.swift
│       ├── HotkeyController.swift
│       ├── ClipboardService.swift
│       ├── FormatDetector.swift
│       ├── ViewerPanelController.swift
│       ├── WebViewBridge.swift
│       └── Resources/web-dist/   # Generated from web build
├── web/                      # TypeScript viewer
│   ├── package.json
│   ├── vite.config.ts
│   └── src/
│       ├── index.html
│       ├── viewer.ts         # Molstar init + API
│       ├── bridge.ts         # Swift <-> JS messaging
│       └── formats.ts
└── scripts/
    ├── build-web.sh
    └── copy-web-dist.sh
```

## Build Commands

```bash
# Web viewer (from web/)
bun install
bun build                    # Outputs to web/dist/

# Full build pipeline
./scripts/build-web.sh        # Build web + copy to macos/Pasteur/Resources/web-dist/

# macOS app
# Build via Xcode or xcodebuild from macos/
```

## Architecture

### Data Flow (Hotkey Path)
1. User presses global hotkey
2. Swift reads clipboard string via `ClipboardService`
3. `FormatDetector` identifies molecular format using heuristics
4. Swift shows preloaded `NSPanel` containing `WKWebView`
5. Swift sends `{format, data}` to JS via `WebViewBridge`
6. JS calls Molstar `loadStructureFromData(...)`
7. JS notifies Swift of success/error

### Swift <-> JS Bridge Protocol

**Swift -> JS** (via `evaluateJavaScript`):
- `load: { id, format, data, options }`
- `clear`
- `export: { id, targetFormat }`

**JS -> Swift** (via `WKScriptMessageHandler` on `pasteur` channel):
- `ready`
- `loaded: { id, stats }`
- `error: { id, message }`
- `exportResult: { id, data }`

### Format Detection Priority
MOL2 > SDF > MOL > PDB > CIF > XYZ (most specific first)

Heuristics:
- MOL2: contains `@<TRIPOS>`
- SDF: contains `$$$$` and `M  END`
- MOL: contains `M  END` and `V2000/V3000`
- PDB: lines start with `ATOM`/`HETATM`/`HEADER`/`MODEL`
- mmCIF: starts with `data_` or contains `_atom_site.`
- XYZ: first line is integer atom count

### Key Performance Requirement
Sub-second clipboard-to-visualization. Achieved by:
- Preloading NSPanel + WKWebView + Molstar on app launch
- Panel kept hidden until invoked
- Hotkey only reads clipboard, sends message, shows panel

### NSPanel Behavior
- Floating/always-on-top
- Non-activating (`NSWindow.StyleMask.nonactivatingPanel`)
- Closes on Esc
- Does not steal focus from terminal

## Security Notes

- Never string-concatenate raw clipboard into JS; always JSON-encode payloads
- Clipboard read only on explicit user action (hotkey/menu click)
- No continuous clipboard scraping by default

## Licensing Constraints

- Molstar: MIT (safe)
- RDKit WASM: BSD (safe for Phase 2 SMILES support)
- Avoid Open Babel (GPL implications)
