<p align="center">
  <img src="https://github.com/SentimeterGG/enso/blob/main/assets/branding/ENSO-Logo-Rounded.png?raw=true" alt="ENSO" width="400"/>
</p>

<h3 align="center">A rhythm game where you draw shapes in time with the music.</h3>

<p align="center">
  <a href="https://github.com/SentimeterGG/enso/releases"><img src="https://img.shields.io/github/v/release/SentimeterGG/enso?label=Release&color=5865F2" alt="Latest release"></a>
  <a href="https://godotengine.org/download"><img src="https://img.shields.io/badge/Godot-4.7-%23478CBF?logo=godot-engine&logoColor=white" alt="Godot 4.7"></a>
</p>

---

> [!WARNING]
> **ENSO is not finished.** It is still in active development, so expect bugs, missing features, and breaking changes. Please report any issues you find on the [issue tracker](https://github.com/SentimeterGG/enso/issues).

> [!NOTE]
> ENSO is currently available for **Windows** and **Android**. macOS and native Linux builds are planned.

---

## Table of Contents

- [About](#about)
- [Downloading the Game](#downloading-the-game)
  - [Latest Release](#latest-release)
- [Installation](#installation)
  - [Windows](#windows)
  - [Android](#android)
- [User Folder](#user-folder)
- [Getting Maps](#getting-maps)
- [Development](#development)
  - [Prerequisites](#prerequisites)
  - [Project Structure](#project-structure)
- [Contributing](#contributing)
- [License](#license)

---

## About

**ENSO** is a free and open-source rhythm game built with **Godot 4.7** and **GDScript**.

Shapes approach a target ring, and you draw each stroke of the shape to the beat. The game includes a built-in level editor for creating and testing your own charts.

---

## Downloading the Game

> [!IMPORTANT]
> **Do not** clone this repository to play the game. Use the download links below instead.

### Latest Release

The latest stable version is **v0.4.0**.

You can view all releases and changelogs on the [releases page](https://github.com/SentimeterGG/enso/releases).

| Platform | Download |
|---|---|
| **Windows** | [Download for Windows](https://github.com/SentimeterGG/enso/releases/latest) |
| **Android** | [Download for Android](https://github.com/SentimeterGG/enso/releases/latest) |

---

## Installation

### Windows

1. Download the latest `enso.x.x.x.exe` from the [releases page](https://github.com/SentimeterGG/enso/releases).
2. Place the `.exe` in a folder of your choice.
3. Run `enso.x.x.x.exe`.

> [!NOTE]
> If Windows reports missing runtime libraries, install the [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe).

### Android

1. Download the latest `enso.x.x.x.apk` from the [releases page](https://github.com/SentimeterGG/enso/releases).
2. Open the downloaded `.apk` file.
3. If prompted, allow your browser or file manager to install apps from unknown sources.
4. Tap **Install** and launch **ENSO**.

> [!NOTE]
> The Android build targets **arm64-v8a** devices.

---

## User Folder

ENSO stores settings, saves, and custom levels separately from the game installation, in Godot's `user://` folder:

| Platform | Path |
|---|---|
| **Windows** | `%appdata%\ENSO` |
| **Linux** (editor) | `~/.local/share/ENSO` |
| **Android** | Managed by the OS in the app's private storage |

Custom levels placed in the `levels` folder inside the user folder will show up in the level selector.

---

## Getting Maps

A selection of levels is bundled with each release. To add more, place chart folders in the `levels` folder inside your [user folder](#user-folder), or create your own using the built-in level editor.

---

## Development

### Prerequisites

| Tool | Version | Notes |
|---|---|---|
| [Godot Engine](https://godotengine.org/download) | **4.7** | Standard build is sufficient — the project uses GDScript, not C# |
| [Git](https://git-scm.com/downloads) | Latest | Required to clone the repository |

### Project Structure

```
├── addons/            # Editor and runtime addons (Discord RPC, editor helpers)
├── android/           # Android build configuration
├── assets/            # Branding, fonts, sounds, and sprites
├── build/             # Local export output (ignored by Git)
├── dev/               # Development tools and notes (ignored by Git)
├── levels/            # Bundled charts and songs
├── resources/         # Themes, shaders, and UI assets
├── scenes/            # Game scenes (menu, gameplay, results, editor, UI)
├── scripts/           # GDScript source code
│   ├── chart/         # Chart data and parsing
│   ├── draw/          # Drawing input and shape recognition
│   ├── game/          # Core gameplay and health
│   ├── judgement/     # Timing windows, accuracy, and hit results
│   ├── loading_system/# Loading screen logic
│   ├── music/         # Music playback and sync
│   ├── note/          # Beat and shape note logic
│   ├── saves/         # Settings persistence
│   ├── settings/      # Settings UI
│   ├── skin/          # Skin loading and management
│   └── ui/            # Menus, level selector, editor, HUD, and updater
├── skin/              # Default skin assets
├── project.godot      # Godot project configuration
└── export_presets.cfg # Export settings for Windows and Android
```

### Running from Source

1. Open **Godot 4.7**.
2. Click **Import** and select `project.godot`.
3. Press **F5** to run the project.

---

## Contributing

Contributions are welcome — bug fixes, features, charts, documentation, and translations alike.

### Workspace Setup

1. **Fork** the [repository](https://github.com/SentimeterGG/enso).
2. **Clone** your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/enso.git
   cd enso
   ```
3. Open `project.godot` in **Godot 4.7**.

### Submitting Your Changes

This repository uses a **commit → rebase → merge** workflow (see [`IMPORTANT.txt`](IMPORTANT.txt)):

1. Create a branch for your work:
   ```bash
   git checkout -b my-change
   ```
2. Commit your changes:
   ```bash
   git add <files>
   git commit -m "Brief description of your change"
   ```
3. Rebase onto the latest `main`:
   ```bash
   git fetch origin
   git rebase origin/main
   ```
4. Push and open a pull request against **`main`**:
   ```bash
   git push origin my-change
   gh pr create
   ```
5. Wait for maintainers to review your code and provide feedback.

### Guidelines

- Follow existing code style and naming conventions.
- Keep PRs focused — one feature or fix per PR.
- Test your changes locally before submitting.
- For large changes, open an issue first to discuss the approach.
- Always state AI usage in PRs and issues, and make sure you can explain and fix any code you submit.

---

## License

No license file is currently included in this repository. Unless stated otherwise, all rights are reserved by the project authors. If you plan to redistribute or reuse the project, please contact the maintainers first.
