# FastCard Copier

A macOS utility for photographers to ingest memory cards as fast as possible with minimum friction.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey) ![Swift](https://img.shields.io/badge/swift-5.9-orange)

---

## What it does

FastCard Copier watches for memory cards, finds all your photos and videos, and transfers them to a destination folder in one tap. Designed for photographers who shoot tethered or ingest into Lightroom, Capture One, or any folder-watched workflow.

- **Auto-detects cards** the moment they mount — no hunting in Finder
- **Large, glanceable status** — file count and ring progress visible from across a room
- **Fast transfer** — 4 concurrent copy streams to saturate card read speed
- **Copy or Move** — keep originals on card, or clear it as you go
- **Auto-start mode** — starts the transfer immediately on card insert if a destination is set
- **Live stats** — throughput (MB/s), ETA, and current filename during transfer
- **SHA-256 verification** — optional read-back pass to confirm every byte arrived intact
- **Folder structure preservation** — optionally reproduce the card's directory hierarchy under a dated session folder
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

## Settings

All settings are accessed via the **gear icon** in the title bar and persist across launches. The main window is intentionally minimal — source card, destination folder, and start button — so there is nothing to configure under pressure.

### Transfer mode

| Mode | Behaviour |
|---|---|
| **Copy — keep originals** (default) | Files are copied; originals remain on the card |
| **Move — clear card** | Files are copied and verified, then the source is deleted only after a confirmed good copy |

### On name collision

Controls what happens when a file with the same name already exists at the destination.

| Setting | Behaviour |
|---|---|
| **Rename** (default) | A numeric suffix is appended — `IMG_0001_2.CR3`, `_3`, etc. No existing data is ever overwritten |
| **Skip if exists** | The existing file is left untouched. Skipped files are tallied and shown on the complete screen. Useful when re-inserting a card you have already ingested |
| **Overwrite** | The existing file is replaced |

### SHA-256 verify

When enabled, after writing each file FastCard Copier reads it back from the destination and compares its SHA-256 hash against the hash computed during the copy. Any mismatch is reported as a checksum failure on the complete screen. See [How transfers work](#how-transfers-work) for details.

### Preserve folder structure

| Setting | Behaviour |
|---|---|
| **Off** (default) | All files land flat in the destination folder; the card's directory hierarchy is ignored |
| **On** | A session folder named `20250115_143205 EOS_DIGITAL` (timestamp + card name) is created inside the destination. The card's full directory tree from the mount point is reproduced inside it — so `DCIM/100CANON/IMG_0001.CR3` on the card becomes `20250115_143205 EOS_DIGITAL/DCIM/100CANON/IMG_0001.CR3` at the destination |

Each transfer run gets its own dated session folder, so consecutive card ingests to the same destination never collide with each other.

### Auto-start

When enabled, the transfer begins automatically the moment a card is inserted, provided a destination folder is already set.

---

## File types recognised

| Category | Extensions |
|---|---|
| RAW | ARW, CR2, CR3, NEF, NRW, ORF, RW2, DNG, RAF, 3FR, ERF, KDC, MRW, PEF, R3D, SRW, X3F |
| JPEG / still | JPG, JPEG, HEIC, HEIF, PNG, TIF, TIFF |
| Video | MP4, MOV, MTS, M2TS, M4V, AVI, MXF |

---

## How transfers work

This section explains what FastCard Copier does under the hood. Understanding it may help you trust the output and diagnose unexpected results.

### Temp-file write strategy

Every file is written to a hidden temporary file (`.xxxxxxxx.tmp`) in the destination directory first. Only after the copy is complete — and verified, if that option is on — is the temporary file atomically renamed to its final filename.

This means:

- **Watch-folder applications never see a partial file.** Lightroom, Capture One, and similar tools that watch a folder for new arrivals will only ever see complete, fully-written files because the file does not exist at its final path until it is ready.
- **A failed copy leaves no debris.** If the copy fails for any reason, the hidden temp file is deleted and nothing appears in the destination.

### SHA-256 verification (optional)

When Verify is enabled, FastCard Copier performs two passes per file:

1. **Write pass** — the source file is read in 4 MB chunks. Each chunk is fed to a SHA-256 hasher as it is written to the temp file. This adds no extra I/O because the source was being read anyway; the CPU overhead of hashing at this stage is negligible (Apple Silicon can hash at ~1–2 GB/s, far faster than card read speeds of ~100–200 MB/s).

2. **Read-back pass** — once writing is complete, the temp file is read back from the destination and hashed independently. The two digests are compared.

If they match, the rename proceeds and the file appears at its final path. If they differ, the temp file is deleted, a checksum failure is recorded, and the source file is left untouched.

**What this catches:** silent write errors (bad sectors, bus errors, filesystem corruption during the write). It does not detect corruption that occurred on the source card before the copy began, because there is nothing to compare against.

When Verify is off, the write pass still happens and the temp-file strategy still applies (so watch-folder apps are still protected), but the read-back pass is skipped. This halves the destination I/O and is appropriate when speed is more important than confirming end-to-end integrity.

### Move mode safety

In Move mode, the source file on the card is only deleted **after** `copyAndVerify` returns successfully. If the copy fails or the checksum does not match, the source is preserved. It is not possible for Move mode to result in data loss due to a failed transfer.

### Filename collision handling

Without the Preserve structure option, all files from a card land in the same flat folder. If two files on the same card share a name (unusual but possible — e.g. two subdirectories both containing `IMG_0001.CR3`) the selected collision mode applies. When Preserve structure is on, files are placed at paths matching their location on the card, so within-card collisions cannot occur.

### Timestamps

After writing each file, the creation date and modification date from the source file are copied to the temp file before it is renamed. The destination file therefore carries the original capture-time filesystem dates, not the ingest time. EXIF metadata embedded in the file content is unaffected — it is copied verbatim as part of the file data.

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
