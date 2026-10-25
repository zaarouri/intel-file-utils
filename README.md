# Intel File Utils

<div align="center">

![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-blue?style=flat-square&logo=apple)
![Architecture](https://img.shields.io/badge/Architecture-Intel%20x86__64-orange?style=flat-square&logo=intel)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Offline](https://img.shields.io/badge/Privacy-100%25%20Offline-success?style=flat-square)

**A native, zero-click file conversion & manipulation tool inspired by [Tangerine](https://tangerineformac.com/), built and optimized exclusively for Intel Macs.**

</div>

---

## ⚡️ Overview

Original Tangerine is restricted to Apple Silicon (`arm64`) Macs on the App Store. **Intel File Utils** brings the exact same fluid, **zero-click drag workflow** to **Intel x86_64 Macs** running macOS 13+ (Ventura, Sonoma, Sequoia).

- **100% Offline & Local**: Zero cloud dependencies, zero external subscriptions, zero telemetry.
- **Pure AppKit & CoreGraphics**: High-performance native macOS UI with smooth glassmorphism, responsive canvas rendering, and zero Electron/web bloat.
- **Zero-Click Radial Wheel**: Drag any file in Finder and tap a modifier key to trigger radial actions right under your cursor.

---

## 🍊 Key Features

### 1. Zero-Click Gesture Radial Wheels
Simply drag any file or group of files in Finder and tap:
* **`⇧ Shift`**: **Format Conversions Wheel**
  * Images: WebP, PDF, PNG, JPG, HEIC, TIFF, BMP.
  * Audio: MP3, M4A, WAV, FLAC, AIFF.
  * Video: MP4, MOV, WebM, GIF, MP3.
  * Documents: PDF, DOCX, TXT, Markdown.
* **`⌘ Command`**: **Powerhouse Tools Wheel**
  * Freeform Crop, Resize & Scale, Create Combined PDF, Compress, Strip EXIF Metadata.
* **`⌃ Control`**: **Quick Actions Wheel**
  * Pin to Floating Shelf, AirDrop, Copy to Clipboard, Move to Folder, Copy File Path, Open in Terminal.

### 2. Studio Freeform Crop & WebP Converter
* **Interactive Freeform Canvas**: Click and drag freely across any image preview to crop custom dimensions or locked ratios (1:1 Square, 16:9 Widescreen, 4:3 Photo, 9:16 Reel/Story, 3:2 Classic).
* **8 Resize Handles & Pan**: 4 corner handles and 4 edge midpoint pills with dynamic cursor tracking and real-time pixel size badge.
* **True WebP Export**: High-efficiency local encoding via Pillow (`RIFF...WEBPVP8`) with up to 98% file size reduction and adjustable quality slider (30% to 100%).
* **Quick Tools**: 90° rotation, horizontal flip, and live Brightness, Contrast, and Saturation adjustments.

### 3. Multi-Image to Vector PDF
* Convert single images or combine multiple photos into high-resolution, multi-page vector PDF documents.
* Scale and resize PDF page boundaries to standard formats (A4, US Letter, 1080p, or custom dimensions).

### 4. Translucent Floating Shelf (`⌘S`)
* Stage files and images across spaces and desktops on a pinned HUD shelf.
* Visual item list with file thumbnails, names, size badges, and single-click batch conversion actions.

---

## ⌨️ Shortcuts Reference

| Shortcut | Action |
| :--- | :--- |
| **`⌘C`** | Open Freeform Crop & WebP Converter on selected file |
| **`⌘W`** | Direct Convert Image(s) to WebP |
| **`⌘P`** | Convert Image(s) or Combine into PDF |
| **`⌘R`** | Resize & Scale Image / PDF |
| **`⌘M`** | Merge Multiple PDFs |
| **`⌘O`** | Quick Convert File picker |
| **`⌘S`** | Toggle Floating Shelf |
| **`⌘Q`** | Quit Intel File Utils |

---

## 🛠️ Building & Installation

### Prerequisites
* macOS 13.0 or later running on an **Intel (x86_64)** Mac.
* Xcode 15+ or Command Line Tools (`xcode-select --install`).
* Python 3 with Pillow (`pip3 install pillow`) for WebP conversion.

### Build from Source
```bash
git clone https://github.com/zaarouri/intel-file-utils.git
cd intel-file-utils
./build_app.sh
```

### Launch
```bash
open "Intel File Utils.app"
```

---

## 🔒 Accessibility Permissions

Because Intel File Utils observes drag gestures and modifier keys globally across Finder, macOS requires Accessibility permissions:
1. Open **System Settings -> Privacy & Security -> Accessibility**.
2. Enable toggle for **Intel File Utils** (or your Terminal if debugging).

---

## 📁 Project Architecture

```
intel-file-utils/
├── Package.swift               # Swift 6 package manifest
├── build_app.sh                # Release compilation & codesign script
├── AppIcon.icns                # Multi-resolution macOS app icon
├── Resources/                  # Menu bar icons & branding
└── Sources/
    ├── AppDelegate.swift       # App lifecycle & accessibility onboarding
    ├── main.swift              # AppKit entry point
    ├── Models/
    │   ├── ConversionMatrix.swift  # Format compatibility matrix
    │   └── ItemDefinitions.swift   # Tool & action definitions
    ├── Radial/
    │   ├── RadialMath.swift        # Geometric trigonometry & hit-testing
    │   ├── RadialMenuView.swift    # Frosted glassmorphism wheel rendering
    │   └── RadialWindowController.swift # Zero-click pop-up panel controller
    ├── Services/
    │   ├── DragMonitorService.swift # Global event tap gesture monitor
    │   ├── FileActionsService.swift # AirDrop, Clipboard, Terminal actions
    │   ├── FileConverterService.swift # WebP, ImageIO, PDFKit, AVFoundation
    │   └── NotificationService.swift  # Modern UserNotifications framework
    └── UI/
        ├── FloatShelfWindow.swift  # Pinned translucent HUD shelf
        ├── ResizeEditorWindowController.swift # Freeform crop studio & editor
        └── StatusItemController.swift # Native status bar menu
```

---

## 📄 License

Distributed under the **MIT License**. See [LICENSE](LICENSE) for details.

Developed with ❤️ for the Intel Mac community by [@zaarouri](https://github.com/zaarouri).
