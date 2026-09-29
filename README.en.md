<div align="center">

<img src="assets/dsh-whale.ico" width="96" alt="DSH Portable" />

# DSH Portable

**Unofficial portable launcher for DeepSeek Harness**<br/>
<sub>[**English**](README.en.md) · [**简体中文**](README.md)</sub>

<a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/Yata-Datacom/DeepSeekHarness-Portable?style=for-the-badge&color=5E81AC&label=Download" alt="release" /></a>
<img src="https://img.shields.io/badge/Windows-10%201809%2B%20%2F%2011%20x64-81A1C1?style=for-the-badge&logo=windows11&logoColor=white" alt="windows" />
<img src="https://img.shields.io/badge/PowerShell-5.1-5E81AC?style=for-the-badge&logo=powershell&logoColor=white" alt="powershell" />
<img src="https://img.shields.io/badge/License-MIT-8FBCBB?style=for-the-badge" alt="MIT" />

</div>

> Unzip, double-click, done. No command line, no Node install, no changes to the host system.

> 🆘 **Stuck? Start with the [troubleshooting manual](docs/TROUBLESHOOTING.md)** - a blocked exe, port 3080 in use, a missing key, an over-long extraction path, a stale browser view: each one has a written answer. For how it works inside, see the **[architecture doc](docs/ARCHITECTURE.md)**.

---

## ⬇️ Download

Download `DSH-Portable.zip` (~**136 MB**, bundled Node runtime, works offline) from **[Releases](../../releases/latest)**.

**Direct link** — `https://github.com/Yata-Datacom/DeepSeekHarness-Portable/releases/latest/download/DSH-Portable.zip`

### 🔐 Verify the download

Every release ships `SHA256SUMS.txt` signed with this project's release key, so you can tell whether the archive really came from here:

```sh
gpg --import assets/certs/release-signing-pub.asc
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
# the signing fingerprint must be A03127AD6D1F8D1D03EAD4969CCC65C393DF8230
```

The bundled `DSH 便携版.exe` is signed with a self-signed certificate. **You do not need to trust it** - the `start DSH.vbs` entry works regardless. If you want fewer Windows app-control prompts, run `trust-signing-cert.cmd` inside the extracted folder (it trusts exactly that one certificate for your user only, and `untrust-signing-cert.cmd` undoes it).

---

## ✨ Features

| | Feature |
| :-- | :-- |
| 🟢 | **Truly portable** — unzip and run, no registry, no PATH changes, never writes `~/.dsh` |
| 🔍 | **Preflight check** — OS version, port conflicts and blockers reported up front |
| 🛡️ | **Never overwrites by default** — a forced overwrite needs triple confirmation |
| 🧹 | **Clean uninstall** — removes every trace it created |
| 🔑 | **Bring your own key** — the package ships zero API keys; the first launch walks you through entering your own |
| 🧪 | **Provable isolation** — bundled `tools\verify-isolation.ps1` compares before/after snapshots to prove zero changes outside the folder |

---

## 🚀 Quick start

```text
1. Download DSH-Portable.zip
2. Extract into a SHORT path (D:\DSH\ recommended, do not bury it deep in Desktop)
3. Double-click   DSH 便携版.exe
4. On first launch, enter your own DEEPSEEK_API_KEY when prompted
```

- **Requirements**: 64-bit Windows 10 **1809 (Build 17763)** or later, Windows 11 included
- **Port**: `3080` by default (it moves to the next free port if that one is taken)
- Starts without a key too — it just warns that none is configured.

The illustrated walkthrough is **[README-使用说明.md](README-使用说明.md)** (in Chinese); the package also ships `使用说明.txt`.

---

## 🗂️ Repository layout

| Path | What it is |
| :-- | :-- |
| `launcher/core.ps1` | Core logic: environment self-check, start/stop, port management, clean uninstall |
| `launcher/launcher.ps1` | WinForms graphical launcher (main window) |
| `src/Launcher.cs` | C# source of the `DSH 便携版.exe` launcher (compiled with the system csc, WinForms) |
| `tools/core-bridge.ps1` | JSON bridge between the C# UI and `core.ps1` (one action per operation) |
| `assets/dsh-whale.ico` | Application icon |
| `entry/` | In-package double-click entry points (`启动 DSH.vbs` / `start-dsh.cmd`) |
| `bin/dsh.cmd` | In-package CLI entry point (brings its own `DSH_HOME` redirection) |
| `build-package.ps1` | Packager: assembles the portable tree + builds the zip + secret-leak scan |
| `tools/verify-isolation.ps1` | Isolation verification (snapshot → repeated start/stop → diff; passes only with zero changes outside the folder) |
| `tests/core.Tests.ps1` / `tests/preflight.Tests.ps1` | Pester unit tests and negative tests |
| `.github/workflows/build.yml` | Test → package → 38-item integrity gates → isolation verification → draft Release |
| `.github/workflows/upstream-watch.yml` / `tools/check-upstream.ps1` | Weekly comparison against the npm upstream; files an issue on any drift |
| `使用说明.txt` / `README-使用说明.md` | Documentation handed to end users |

> Build artifacts (`DSH-Portable\`, `*.zip`) are **not committed** — source lives in the repo, binaries live in Releases. This is standard GitHub practice.

---

## 🛠️ Build your own

You need an already-installed DeepSeek Harness directory (with `node\` runtime):

```powershell
powershell -ExecutionPolicy Bypass -File build-package.ps1 `
    -Src "D:\path\to\DeepSeekHarness" `
    -Out "D:\out"
```

Without `-Src` it is inferred automatically (both the dev layout `<src>\pack\` and the repo root are recognised). Output:

```text
<Out>\DSH-Portable\       portable tree (unzip and run)
<Out>\DSH-Portable.zip    the archive you hand to users
```

The build **never writes a single secret**; at the end it scans the whole package and aborts immediately if a real key from this machine is found.

---

## 🔧 Build & Release

**Fully automated — nothing to build locally.** Push a tag and you get a **draft** Release to review, then publish manually.

```text
git tag v1.0.1 && git push --tags
        |
        v   GitHub Actions . windows-latest . .github/workflows/build.yml
  1  read deps.json             pin exact versions of node / dsh / every plugin
  2  install dsh into node dir  identical to the local packaging layout
  3  ci-prepare.ps1             seed ~/.dsh + pnpm install --frozen-lockfile + staging links
  4  assert 3 plugins composed  guards against "installed but not active" silent failures
  5  build-package.ps1          produces DSH-Portable\
  6  verify-package.ps1         38 integrity gates (structure/plugins/seed/privacy/no symlinks/no secrets)
  7  tar + SHA256               produces DSH-Portable.zip + SHA256SUMS.txt
  8  upload artifact (kept 14 days)
  9  end-to-end isolation check really starts/stops the web service, proving zero host changes
 10  create **draft** Release   you review it and publish manually
```

**Why it is trustworthy**

| | |
| :-- | :-- |
| Reproducible deps | `ci-profile/web/pnpm-lock.yaml` records a `sha512` integrity hash for every package, and git deps are pinned down to the commit |
| Clean environment | The build runs on a **brand-new machine**, so the isolation verdict is stronger than a local run |
| Order matters | **Zip first, end-to-end second**: running dsh makes the package self-heal symlinks, tar follows them and the size doubles |
| No fake green | Any failing step stops the pipeline; the artifact must also clear all 38 gates before it may be packaged |
| Verifiable output | The Release ships `SHA256SUMS.txt` so downloads can be checked |

---

## 🧪 Verify isolation

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-isolation.ps1 -Rounds 3
```

Snapshot the system → start/stop repeatedly (CLI + web service) → snapshot again → diff item by item.
CI runs this on every build (`-Rounds 2`) — on a clean machine, which makes the verdict more convincing.
An output of `✔ 通过：包外环境【零改动】` means `~/.dsh`, PATH and the registry were untouched, and no files were left behind in document folders.

---

## ⚖️ Third-party

| Component | License |
| :-- | :-- |
| [Node.js](https://nodejs.org/) v22 (bundled in the release zip) | MIT |
| [`@deepseek-ai/dsh`](https://www.npmjs.com/package/@deepseek-ai/dsh) (bundled) | MIT © 2026 DeepSeek |
| Plugins `dsh-whale-galgame` · `dsh-whale-widget` · `open-sea-skin` | Respective authors |

This repo **contains only the launcher and the packaging scripts**; the bundled components above remain the property of their respective authors. See [NOTICE.md](NOTICE.md).

---

## ⚠️ Disclaimer

This is an **unofficial** third-party portable wrapper, not affiliated with or endorsed by DeepSeek. Please comply with the terms of service of `@deepseek-ai/dsh` and its services.

---

<div align="center">
<sub>MIT License · © 2026 Yata-Datacom</sub>
</div>
