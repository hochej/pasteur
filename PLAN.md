
Pasteur Developer Implementation Guide (Swift + Molstar)

This is a practical end-to-end guide for a developer starting from zero.

⸻

1) Product definition

1.1 Core user story

“I’m SSH’d into a remote cluster. I copy a molecule text (PDB/mmCIF/XYZ/MOL/SDF/etc.) into my clipboard. I hit a global hotkey. A small viewer pops up instantly and renders it.”

1.2 MVP scope (recommended)

Supported inputs (clipboard plain text):
	•	PDB / PDBQT
	•	mmCIF / CIF
	•	XYZ
	•	MOL / SDF
	•	MOL2
	•	GRO (optional)

Molstar supports these structure formats natively ￼.

Trigger:
	•	global hotkey (default)
	•	menu bar item (“Visualize Clipboard”)

Outputs (MVP):
	•	“Copy original text back to clipboard”
	•	“Save session” (Mol* session .molx) as a file (good reproducibility)
	•	(Optional) screenshot export

Note: True “convert to arbitrary alternative formats” is non-trivial; do it as a Phase 2 feature (see Section 10).

1.3 Non-goals (for MVP)
	•	handling enormous trajectories / volumetric maps
	•	remote fetching from PDB, EMDB, etc. (Pasteur’s point is clipboard, no network)
	•	perfect SMILES support (Phase 2/3)

⸻

2) Tech stack

2.1 macOS shell
	•	Swift + AppKit
	•	NSStatusItem menu bar app
	•	NSPanel for viewer window
	•	global hotkey (MASShortcut or KeyboardShortcuts, or Carbon directly)
	•	NSPasteboard clipboard read/write

2.2 Viewer frontend
	•	TypeScript + Vite (no heavy UI framework needed)
	•	Molstar from npm (bundle locally; avoid CDNs)

Molstar’s Viewer API includes Viewer.create(...) and loadStructureFromData(data, format) for loading a structure directly from an in-memory string ￼.

2.3 Optional Phase 2: SMILES conversion
	•	RDKit (WASM) in the web layer
	•	RDKit is BSD licensed ￼
	•	Avoid bundling Open Babel unless you want GPL implications ￼

2.4 Licensing notes
	•	Molstar is MIT licensed ￼
	•	RDKit BSD (good for shipping) ￼
	•	Indigo is Apache 2.0 if you ever want a native conversion engine ￼
	•	Open Babel is GPL (avoid if you don’t want GPL distribution constraints) ￼

⸻

3) High-level architecture

3.1 Component diagram

Pasteur.app
├─ AppKit Shell (Swift) ├─ StatusItemController (menu bar icon + menu) ├─ HotkeyController (global shortcut) ├─ ClipboardService (NSPasteboard read/write) ├─ FormatDetector (heuristics) ├─ ViewerPanelController (NSPanel + WKWebView) └─ Preferences (SwiftUI or AppKit panel) └─ Web Viewer (bundled assets)
 ├─ index.html
 ├─ viewer.ts (Molstar init + API)
 ├─ bridge.ts (Swift <-> JS messaging)
 └─ (optional) rdkit-wasm for SMILES -> SDF/MOL

3.2 Data flow (hotkey path)
	1.	User presses hotkey
	2.	Swift reads clipboard string
	3.	Swift detects format
	4.	Swift shows panel (already preloaded)
	5.	Swift sends {format, data} to JS via bridge
	6.	JS calls Molstar loadStructureFromData(...)
	7.	JS notifies Swift “loaded” or “error”

⸻

4) Repository layout & build pipeline

4.1 Suggested repo structure

pasteur/
├─ macos/ ├─ Pasteur.xcodeproj └─ Pasteur/ ├─ AppDelegate.swift ├─ StatusItemController.swift ├─ HotkeyController.swift ├─ ClipboardService.swift ├─ FormatDetector.swift ├─ ViewerPanelController.swift ├─ WebViewBridge.swift └─ Resources/ └─ web-dist/ (generated) ├─ web/ ├─ package.json ├─ vite.config.ts └─ src/ ├─ index.html ├─ viewer.ts ├─ bridge.ts └─ formats.ts └─ scripts/
 ├─ build-web.sh
 └─ copy-web-dist.sh

4.2 Build strategy
	•	web/ builds via pnpm build → outputs web/dist/
	•	Xcode Run Script build phase runs scripts/build-web.sh and copies dist → macos/Pasteur/Resources/web-dist/

Key requirement: the app must run fully offline (Molstar assets bundled).

⸻

5) macOS app implementation (Swift/AppKit)

5.1 App lifecycle

Use an NSApplicationDelegate (AppKit) even if you use SwiftUI for Preferences.
	•	On launch:
	•	set activation policy to accessory if you want no Dock icon (common for menu bar apps)
	•	create the status item
	•	preload the viewer WKWebView (important for “sub-second”)

5.2 Menu bar status item

Create NSStatusItem with:
	•	“Visualize Clipboard” (same action as hotkey)
	•	“Preferences…”
	•	“Quit”

5.3 Global hotkey

Options:
	•	MASShortcut (battle-tested)
	•	KeyboardShortcuts (nice Swift API)
	•	or direct Carbon RegisterEventHotKey

Important macOS caveat: some modifier combinations (notably “Option-only” style combos) have had OS-level regressions on macOS 15 (“Sequoia”) in some APIs, so pick a conservative default like ⌃⌥⌘M and allow users to customize. ￼

5.4 Viewer window behavior: NSPanel

Use an NSPanel configured to behave like a quick preview:
	•	floating / always-on-top
	•	closes on Esc
	•	appears centered or near cursor
	•	does not steal focus (terminal stays active)

NSWindow.StyleMask.nonactivatingPanel is explicitly intended for “panel that does not activate the owning app.” ￼

Practical UX recommendation:
	•	Panel is non-activating by default.
	•	If user clicks inside the viewer, you may optionally allow focus (configurable), because interaction with Molstar UI might be easier when focused.

5.5 Clipboard service

MVP: read plain text.

final class ClipboardService {
 private let pb = NSPasteboard.general

 func readString() -> String? {
 pb.string(forType: .string)
 }

 func writeString(_ s: String) {
 pb.clearContents()
 pb.setString(s, forType: .string)
 }
}

Privacy principle:
	•	Don’t continuously scrape clipboard by default.
	•	Read clipboard on explicit user action (hotkey/menu click).
	•	If you add “auto-detect on clipboard change” later, make it opt-in.

⸻

6) Format detection

6.1 Supported formats (MVP)

Use Molstar-supported structure formats as your baseline ￼:
	•	pdb
	•	cif / mmcif (you’ll pass one canonical)
	•	xyz
	•	mol
	•	sdf
	•	mol2
	•	gro (optional)

6.2 Practical heuristics (Swift)

Implement a fast detector that returns:
	•	format: String compatible with Molstar’s loadStructureFromData
	•	or nil meaning “unrecognized”

Heuristic ideas:
	•	MOL2: contains @<TRIPOS>
	•	SDF: contains $$$$ record separators (often) and M END
	•	MOL: contains M END and “V2000/V3000” somewhere in header block
	•	PDB: many lines start with ATOM / HETATM / HEADER / MODEL
	•	mmCIF: starts with data_ or contains _atom_site. fields
	•	XYZ: first non-empty line is an integer atom count, second line is comment, then Element x y z lines

Also do sanity checks:
	•	minimum length
	•	reject clipboard that’s obviously not molecular (e.g., JSON, source code)

6.3 Keep it deterministic

If multiple heuristics match, pick the most specific first (e.g., MOL2 > SDF > MOL > PDB > CIF > XYZ).

⸻

7) WKWebView embedding + Swift↔JS bridge

7.1 Load local assets

Bundle web-dist/ into the app resources and load index.html via loadFileURL.

You want something like:
	•	webRoot = Bundle.main.resourceURL/.../web-dist/
	•	index = webRoot/app/index.html (depending on your Vite output)

Then:

webView.loadFileURL(indexURL, allowingReadAccessTo: webRootURL)

7.2 Bridge design

Use:
	•	Swift → JS: evaluateJavaScript(...) with JSON payload
	•	JS → Swift: WKScriptMessageHandler (e.g. pasteur channel)

Define a small message protocol:

Swift → JS
	•	load: { id, format, data, options }
	•	clear
	•	export: { id, targetFormat }

JS → Swift
	•	ready
	•	loaded: { id, stats }
	•	error: { id, message }
	•	exportResult: { id, data }

7.3 Avoid injection issues

Do not string-concatenate raw clipboard text into JS. Always JSON-encode the payload and pass it as an object literal.

Pattern:

struct LoadRequest: Codable {
 let id: String
 let format: String
 let data: String
}

func sendLoad(_ req: LoadRequest) {
 let jsonData = try! JSONEncoder().encode(req)
 let json = String(data: jsonData, encoding: .utf8)!

 let js = "window.Pasteur?.loadFromNative(\(json));"
 webView.evaluateJavaScript(js)
}


⸻

8) Web viewer implementation (TypeScript + Vite + Molstar)

8.1 Create Molstar viewer instance

In viewer.ts:
	•	create the Molstar Viewer inside a full-screen div
	•	disable any UI you don’t want (Molstar viewer options allow toggling panels; see its Viewer options typing) ￼
	•	expose a global API: window.Pasteur = { loadFromNative, clear, export... }

Molstar’s Viewer API supports loadStructureFromData(data, format) directly ￼.

8.2 Handle repeated loads quickly

Don’t recreate the viewer per invocation. Keep a single viewer instance and:
	•	clear previous structure/state
	•	load new data
	•	optionally set camera/representation presets

8.3 Minimal UI overlay

You can implement a lightweight overlay in plain HTML:
	•	“Copy” dropdown (copies generated output / original)
	•	“Save…” button
	•	“Close” button (or just let Esc close on native side)

⸻

9) Achieving “sub-second copy → visualize”

This is mostly about not paying startup costs on hotkey.

9.1 Preload strategy
	•	On app launch, create the NSPanel and the WKWebView, load Molstar assets immediately.
	•	Keep the panel hidden until invoked.
	•	First hotkey should only:
	•	read clipboard
	•	send JS message
	•	show panel

9.2 Rendering strategy
	•	If clipboard changes frequently, don’t auto-load. Only load on trigger.
	•	For large structures, show a “Loading…” overlay (JS side) while Molstar parses.

⸻

10) Export & conversion strategy

10.1 MVP export (easy, useful)
	•	Copy original input back to clipboard
	•	Save Molstar session (.molx) if feasible via Molstar’s session saving features (Molstar supports session/state saving; sessions include input data in .molx in many contexts) ￼
	•	Screenshot export (native or Molstar screenshot tool)

This already covers many “share what I’m looking at” workflows.

10.2 Phase 2: true format conversion

You have three realistic routes:
	1.	RDKit WASM for small molecules (recommended)
	•	SMILES ⇄ SDF/MOL/XYZ
	•	generate 3D conformers for SMILES
	•	licensing is friendly (BSD) ￼
	2.	Indigo toolkit (native)
	•	permissive Apache 2.0 ￼
	•	would require bundling native libs + Swift/Rust bindings
	3.	Open Babel
	•	very capable, but GPL licensing implications for distribution ￼

10.3 Phase 2 SMILES support (practical plan)
	•	Detect “SMILES-like” clipboard: single line, limited charset, not matching other formats.
	•	In JS:
	•	mol = RDKit.get_mol(smiles)
	•	add Hs, embed 3D, optimize
	•	molBlock = mol.get_molblock() or SDF
	•	Feed molBlock to Molstar with format = 'mol' or sdf' (both are supported inputs) ￼

⸻

11) Error handling & UX

11.1 Unrecognized clipboard
	•	Don’t pop the panel; instead show a brief native toast/popup:
	•	“Pasteur: Clipboard doesn’t look like a supported molecule format.”

11.2 Parse errors
	•	Show panel with an error overlay (so the user can copy/paste again)
	•	Provide “Copy error details” for debugging

11.3 Preferences
	•	Hotkey customization
	•	“Open viewer on clipboard change” (off by default)
	•	Default representation preset (cartoon, ball-and-stick, surface)
	•	“Always on top” toggle

⸻

12) Testing plan

12.1 Unit tests (Swift)
	•	FormatDetector: feed sample fixtures for each format and assert the detected format.
	•	ClipboardService: can be lightly tested, but mostly integration.

12.2 Integration tests (manual checklist)
	•	Copy each sample format → hotkey → renders
	•	Very large PDB/mmCIF → still responsive
	•	Close/open repeatedly → no leaks/crashes
	•	Hotkey works when terminal is focused
	•	Panel behavior: does not steal focus (if configured)

⸻

13) Packaging & distribution notes (macOS)
	•	If distributing outside Mac App Store:
	•	code sign + notarize (standard macOS distribution hygiene)
	•	If you make it a pure menu bar app:
	•	set activation policy appropriately
	•	ensure “Quit” is always available from the menu bar


⸻

14) Milestones (recommended execution order)

Milestone 0 — Spike
	•	Menu bar app
	•	Show panel with WKWebView
	•	Load Molstar locally

Milestone 1 — MVP viewer
	•	Global hotkey
	•	Clipboard read
	•	Format detection (PDB/mmCIF/XYZ/MOL/SDF/MOL2)
	•	loadStructureFromData bridge working ￼

Milestone 2 — Polish
	•	Non-activating panel behavior ￼
	•	Error UI
	•	Preferences for hotkey (and safe defaults given macOS modifier quirks) ￼

Milestone 3 — Export + SMILES (optional)
	•	RDKit WASM integration (SMILES → MOL/SDF)
	•	Copy/export flows
