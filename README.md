# FileWheel

A Mac menu-bar app inspired by the GTA V weapon wheel. Hold **⌘** while dragging a file and a liquid-glass wheel sweeps open beside it. Drop the file on a slice to convert it; drop it on the centre to AirDrop it. The converted copy is saved to your Desktop and the original is never changed.

| Dragging a… | Can become |
| --- | --- |
| Image (PNG, JPG, HEIC, TIFF, GIF, BMP) | any other image type, or PDF |
| PDF | PNG, JPG, TIFF (one image per page) or TXT |
| Video (MOV, MP4, M4V) | another video type, or M4A audio |
| Audio (M4A, WAV, AIFF, CAF) | another audio type |

## Build

Needs macOS 15 or later and Xcode (or the Command Line Tools).

```
scripts/build-app.sh     # makes build/FileWheel.app
scripts/make-dmg.sh      # makes build/FileWheel-<version>.dmg
swift test               # runs the conversion tests
```

To keep macOS permissions between builds, put a signing identity in `scripts/local.env` (not committed):

```
SIGN_IDENTITY=<certificate name or hash>
```

For troubleshooting, start the app with `FILEWHEEL_DEBUG=1` to write a log to `/tmp/filewheel.log`.
