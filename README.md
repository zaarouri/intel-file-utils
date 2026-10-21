# intel-file-utils

A native macOS rebuild of [Tangerine](https://tangerineformac.com/) specifically compiled and optimized for **Intel x86_64 Macs** running macOS 13+.

Original Tangerine is an Apple-Silicon-only (`arm64`) Mac App Store utility. This project brings the exact same **zero-click offline drag workflow** to Intel Macs.

## 🍊 Features

- **100% Offline & Native Intel x86_64**: Zero cloud dependencies, zero external subscriptions. Runs directly on Intel hardware.
- **Zero-Click Radial Menu**:
  - Drag a file & tap **`⇧ Shift`**: Conversion Wheel (WebP, PDF, PNG, JPG, HEIC, MP3, MP4).
  - Drag a file & tap **`⌘ Command`**: Quick Tools (Freeform Crop, Resize & Edit, Combine into PDF, Compress, Metadata, Frame).
  - Drag a file & tap **`⌃ Control`**: Action Wheel (Floating Shelf, AirDrop, Copy, Move, Copy Path, Terminal).
- **Interactive Freeform Crop & WebP Converter**:
  - Drag freely across any image preview to crop custom dimensions.
  - 8 resize handles (4 corners + 4 edges) and move/pan within crop box.
  - High-compression, pristine WebP export (`.webp`) via Pillow.
- **Image to Multi-Page PDF**:
  - Combine multiple photos into a crisp vector PDF document.
- **Interactive PDF Page Scaler**:
  - Resize PDF pages to A4, US Letter, 1080p, or custom dimensions.
- **Floating Shelf**:
  - Pin dragged files onto a translucent floating shelf (`⌘S`) to stage files across workspaces.

## 🚀 Running floating-utils-intel-mac

To launch the compiled app:
```bash
open /Users/mac/Desktop/TangerineIntel/floating-utils-intel-mac.app
```

## 🛠️ Accessibility Permissions

Because `floating-utils-intel-mac` detects when you are dragging a file and tapping modifier keys in Finder, macOS requires Accessibility access:
1. Open **System Settings -> Privacy & Security -> Accessibility**.
2. Add or toggle **floating-utils-intel-mac** (or your Terminal/IDE if running from terminal).

