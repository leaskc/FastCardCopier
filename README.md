# FastCard Copier

A macOS utility for photographers to ingest memory cards as fast as possible with minimum friction.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey) ![Swift](https://img.shields.io/badge/swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-blue)

---

## What it does

FastCard Copier watches for memory cards, finds all your photos and videos, and transfers them to a destination folder in one tap. Designed for photographers who shoot tethered or ingest into Lightroom, Capture One, or any folder-watched workflow.

- **Auto-detects cards** the moment they mount — no hunting in Finder
- **Large, glanceable status** — file count and ring progress visible from across a room
- **Fast transfer** — 4 concurrent copy streams to saturate card read speed
- **Copy or Move** — keep originals on card, or clear it as you go
- **Auto-copy mode** — starts the transfer immediately on card insert if a destination is set
- **Live stats** — throughput (MB/s), ETA, and current filename during transfer
- **Light and dark mode** — toggle independently of system appearance

---

## States

| State | Description |
|---|---|
| **Idle** | Waiting for a card to be inserted |
| **No destination** | Card detected, but no ingest folder has been chosen yet |
| **Ready** | Card detected, destination set — shows RAW / JPG / video counts and total size |
| **Transferring** | Ring progress with animated file countdown, live throughput and ETA |
| **Complete** | Green confirmation with transfer summary; eject and Reveal in Finder actions |

---

## File types recognised

| Category | Extensions |
|---|---|
| RAW | ARW, CR2, CR3, NEF, NRW, ORF, RW2, DNG, RAF, 3FR, ERF, KDC, MRW, PEF, R3D, SRW, X3F |
| JPEG / still | JPG, JPEG, HEIC, HEIF, PNG, TIF, TIFF |
| Video | MP4, MOV, MTS, M2TS, M4V, AVI, MXF |

---

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ to build

---

## Building

```bash
git clone https://github.com/leaskc/FastCardCopier.git
open FastCardCopier.xcodeproj
```

Set a Development Team in **Signing & Capabilities** then build and run (`⌘R`).

> The build number is stamped automatically from the git commit count on every build. The marketing version (`MARKETING_VERSION` in `project.pbxproj`) follows semantic versioning and is bumped manually for releases.

---

## Design

Follows the native macOS aesthetic: vibrancy-tinted gradient backgrounds, SF Pro Rounded for numerals, semi-transparent card panels with fine borders, and system blue (`#0a84ff`) as the primary accent. Light and dark appearances are fully supported with a toggle in the title bar.
