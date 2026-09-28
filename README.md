<div align="center">

<img src="assets/dsh-whale.ico" width="96" alt="DSH Portable" />

# DSH 便携版

**非官方 · DeepSeek Harness 绿色便携启动器**<br/>
<sub>[**English**](README.en.md) · [**简体中文**](README.md)</sub>

<a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/Yata-Datacom/DeepSeekHarness-Portable?style=for-the-badge&color=5E81AC&label=Download" alt="release" /></a>
<img src="https://img.shields.io/badge/Windows-10%201809%2B%20%2F%2011%20x64-81A1C1?style=for-the-badge&logo=windows11&logoColor=white" alt="windows" />
<img src="https://img.shields.io/badge/PowerShell-5.1-5E81AC?style=for-the-badge&logo=powershell&logoColor=white" alt="powershell" />
<img src="https://img.shields.io/badge/License-MIT-8FBCBB?style=for-the-badge" alt="MIT" />

</div>

> 解压 → 双击 → 就能用。**同学不需要碰命令行，不需要装 Node，不会弄坏原有环境。**

---

## ⬇️ 下载

到 **[Releases](../../releases/latest)** 下载 `DSH-Portable.zip`（约 **136 MB**，含完整 Node 运行时，离线可用）。

**直链** — `https://github.com/Yata-Datacom/DeepSeekHarness-Portable/releases/latest/download/DSH-Portable.zip`

---

## ✨ 特点

| | 说明 |
| :-- | :-- |
| 🟢 | **绿色便携** — 整包解压即用，不动注册表、不改 PATH、不写 `~/.dsh` |
| 🔍 | **启动前环境预检** — 系统版本 / 端口占用 / 冲突检测，不满足会明确告诉你 |
| 🛡️ | **冲突默认拒装** — 需要覆盖时必须三重确认 |
| 🧹 | **干净卸载** — 一键移除包内所有痕迹 |
| 🔑 | **密钥自填** — 包内绝不包含任何 API key；首次启动引导填写自己的 |
| 🧪 | **环境隔离可自证** — 内置 `tools\verify-isolation.ps1`，快照前后对比证明包外零改动 |

---

## 🚀 快速开始

```text
1. 下载 DSH-Portable.zip
2. 解压到一个【短路径】目录（推荐 D:\DSH\ ，别放桌面深层目录）
3. 双击   DSH 便携版.exe
4. 首次启动按提示填入自己的 DEEPSEEK_API_KEY
```

- **系统要求**：64 位 Windows 10 **1809 (Build 17763)** 或 Windows 11 以上
- **端口**：默认 `3099`（可在启动器里改）
- 没有密钥也可以启动，只会提示未配置。

详细的图文说明见 **[README-使用说明.md](README-使用说明.md)**；包内另附 `使用说明.txt`。

---

## 🗂️ 仓库内容

| 路径 | 说明 |
| :-- | :-- |
| `launcher/core.ps1` | 核心逻辑：环境自检、启动/停止、端口管理、干净卸载 |
| `launcher/launcher.ps1` | WinForms 图形启动器（主界面） |
| `src/Launcher.cs` | 启动器 `DSH 便携版.exe` 的 C# 源码（用系统自带 csc 编译，WinForms） |
| `tools/core-bridge.ps1` | C# 界面与 `core.ps1` 之间的 JSON 桥（每个操作一个动作） |
| `assets/dsh-whale.ico` | 应用图标 |
| `entry/` | 包内双击入口（`启动 DSH.vbs` / `start-dsh.cmd`） |
| `bin/dsh.cmd` | 包内 CLI 入口（自带 `DSH_HOME` 重定向） |
| `build-package.ps1` | 打包器：组装绿色目录 + 生成 zip + 密钥泄漏扫描 |
| `tools/verify-isolation.ps1` | 环境隔离验证（快照 → 反复启停 → 对比，包外零改动才通过） |
| `tests/core.Tests.ps1` / `tests/preflight.Tests.ps1` | Pester 单测与负向测试 |
| `.github/workflows/build.yml` | 测试 → 打包 → 38 项完整性闸门 → 隔离验证 → 草稿 Release |
| `.github/workflows/upstream-watch.yml` / `tools/check-upstream.ps1` | 每周比对 npm 上游版本，有漂移就开 issue |
| `使用说明.txt` / `README-使用说明.md` | 发给使用者的说明文档 |

> 打包产物（`DSH-Portable\`、`*.zip`）**不入库** —— 源码在仓库，成品在 Releases。这是 GitHub 的常规做法。

---

## 🛠️ 自己打包

需要一份已安装好的 DeepSeek Harness 目录（含 `node\` 运行时）：

```powershell
powershell -ExecutionPolicy Bypass -File build-package.ps1 `
    -Src "D:\path\to\DeepSeekHarness" `
    -Out "D:\out"
```

不加 `-Src` 时会自动推断（开发布局 `<src>\pack\` 与仓库根目录都能识别）。产物：

```text
<Out>\DSH-Portable\       绿色便携目录（解压即用）
<Out>\DSH-Portable.zip    分发给使用者的压缩包
```

打包过程**全程不写入任何密钥**，收尾会扫描整个包，发现本机真实 key 立即中止。

---

## 🔧 构建与发布

**全程自动，本机不需要打包。** 打一个 tag 就产出**草稿** Release，过目后手动 publish。

```text
git tag v1.0.1 && git push --tags
        |
        v   GitHub Actions . windows-latest . .github/workflows/build.yml
  1  读 deps.json               锁定 node / dsh / 每个插件的精确版本
  2  装 dsh 到 node 目录          与本地打包布局完全一致
  3  ci-prepare.ps1            铺 ~/.dsh + pnpm install --frozen-lockfile + staging 链接
  4  断言 3 个插件已 composed     防"装了但没生效"的静默失效
  5  build-package.ps1         产出 DSH-Portable\
  6  verify-package.ps1        38 项完整性闸门（结构/插件/seed/隐私/零符号链接/无密钥）
  7  tar + SHA256              产出 DSH-Portable.zip + SHA256SUMS.txt
  8  上传 artifact（保留 14 天）
  9  端到端隔离验证              真的启动/停止 Web 服务，证明包外环境零改动
 10  建**草稿** Release           你看过再手动 publish
```

**为什么可以信**

| | |
| :-- | :-- |
| 依赖可复现 | `ci-profile/web/pnpm-lock.yaml` 记录每个包的 `sha512` 完整性哈希，git 依赖连 commit 一起锁 |
| 环境干净 | 构建跑在**全新机器**上，隔离验证的结论比在本机跑更有说服力 |
| 顺序有讲究 | **先压缩、再跑端到端**：跑 dsh 会让包内自愈出符号链接，tar 会跟进导致体积翻倍 |
| 不给假绿 | 任一步失败即停；成品还要过 38 项闸门才允许打包 |
| 产物可核对 | Release 附 `SHA256SUMS.txt`，下载后可比对 |

---

## 🧪 验证环境隔离

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-isolation.ps1 -Rounds 3
```

给系统拍快照 → 反复启动/停止（CLI + Web 服务）→ 再拍快照 → 逐项对比。
CI 每次构建都会自动跑一遍（`-Rounds 2`）——跑在干净机器上，结论更有说服力。
输出 `✔ 通过：包外环境【零改动】` 表示没有改 `~/.dsh`、PATH、注册表，也没在文档目录留下文件。

---

## ⚖️ 第三方组件

| 组件 | 许可 |
| :-- | :-- |
| [Node.js](https://nodejs.org/) v22（随发行包内置） | MIT |
| [`@deepseek-ai/dsh`](https://www.npmjs.com/package/@deepseek-ai/dsh)（随发行包内置） | MIT © 2026 DeepSeek |
| 插件 `dsh-whale-galgame` · `dsh-whale-widget` · `open-sea-skin` | 各自作者所有 |

本仓库**只包含启动器与打包脚本**；发行包内的上述组件版权归各自作者。详见 [NOTICE.md](NOTICE.md)。

---

## ⚠️ 免责声明

本项目为**非官方**的第三方便携封装，与 DeepSeek 无隶属或背书关系。请遵守 `@deepseek-ai/dsh` 及其服务的使用条款。

---

<div align="center">
<sub>MIT License · © 2026 Yata-Datacom</sub>
</div>
