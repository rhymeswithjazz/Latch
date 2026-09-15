# Latch

Name: Latch

Tagline: Walk away. It locks.

The tagline describes the intended finished product. Current builds remain diagnostic prototypes until hardware acceptance is complete.

## Assets

- `Resources/Latch.png`: generated master artwork, with transparency.
- `Resources/Latch.icns`: macOS icon containing standard and Retina sizes.
- The menu bar mark is a separate native vector drawing. It uses a solid latch during observation and an outline while paused.

Run `python3 scripts/package_icon.py` to rebuild the icon bundle. The generated master is kept unchanged; packaging only scales copies for macOS icon sizes. The ICNS container follows HighDock's PNG-chunk packaging approach.

## Generation

Created with the built-in imagegen tool. Final prompt:

> Use case: stylized-concept. Asset type: production macOS application icon for Latch, a quiet Apple Watch proximity locking utility. Create one square 1024x1024 icon. A single beautifully machined brushed-silver horizontal sliding door latch, in the closed position, centered on a deep midnight-blue rounded-square tile. Make the latch a simple bold silhouette: broad rounded rectangular housing on the left, one solid horizontal silver bolt entering a small separate silver keeper on the right, with a subtle raised vertical thumb grip on the bolt. Front-on, restrained near-orthographic product render, softly bevelled edges, fine silver texture, soft light from upper left, tiny teal inset on the housing as the sole color accent. The latch occupies about 65 percent of the tile width and reads clearly at small sizes. Quiet premium native Mac utility aesthetic, restrained depth, beautiful dark navy-to-midnight surface. The tile fills about 88 percent of the canvas, with macOS-style rounded corners and actual transparent pixels outside it, no opaque outer background. No text, no letters, no padlock, no watch, no computer, no screws or tiny detail, no extra objects, no watermark, no mockup presentation. A finished app icon asset, not a sheet of concepts.

The returned master is 1254 × 1254 pixels with an alpha channel. It was reviewed before packaging.

## Identity continuity

The public app and executable are Latch. Preserve `com.rhymeswithjazz.Unlocker`, the `Unlocker` Application Support directory, `UnlockerDiagnostics` window autosave key, and existing settings schema. These are installed identities, not product copy. Swift targets retain their existing names to keep this change focused on branding.
