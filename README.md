<p align="right">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <img src="docs/readme-screenshot-1.jpg" alt="UsageBar overview screenshot" width="78%">
</p>

<p align="center">
  <img src="docs/readme-screenshot-2.jpg" alt="UsageBar provider details screenshot" width="39%">
  <img src="docs/readme-screenshot-3.jpg" alt="UsageBar settings screenshot" width="39%">
</p>

<h1 align="center">UsageBar</h1>

<p align="center">
  <strong>Track every AI subscription, quota, and cost — right from your macOS menu bar.</strong>
</p>

<p align="center">
  <a href="https://github.com/SHLE1/usage-bar/releases/latest">
    <img src="https://img.shields.io/github/v/release/SHLE1/usage-bar?style=flat-square" alt="Release">
  </a>
  <a href="https://github.com/SHLE1/usage-bar/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/SHLE1/usage-bar?style=flat-square" alt="License">
  </a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.0-orange?style=flat-square" alt="Swift">
</p>

---

**UsageBar** is a lightweight macOS menu bar app that aggregates usage data from 13+ AI providers into a single dashboard. It auto-discovers credentials from [OpenCode](https://opencode.ai), standalone CLI tools, macOS Keychain, editor configs, and browser cookies — zero manual setup required.

## Installation

### Homebrew (Recommended)

```bash
brew install --cask SHLE1/tap/usage-bar
```

### Direct Download

Download the latest `.dmg` from the [**Releases**](https://github.com/SHLE1/usage-bar/releases/latest) page, open it, and drag **UsageBar** to your Applications folder.

UsageBar can check for new versions from the menu via **Check for Updates...**. Releases are currently unsigned, so update checks point to the GitHub release page for manual installation instead of replacing the app automatically. macOS Gatekeeper may require manual approval after installing an update:

```bash
xattr -cr "/Applications/UsageBar.app"
```

## Features

### 🔍 Unified Dashboard

All your AI providers in one menu bar dropdown — pay-as-you-go costs and quota-based remaining percentages at a glance.

```
─────────────────────────────
Pay-as-you-go: $37.61
  OpenRouter       $37.42    ▸
  OpenCode           $0.19   ▸
─────────────────────────────
Quota Status: $219/m
  Copilot (0%)               ▸
  Claude: 0%, 100%           ▸
  Kimi for Coding: 0%, 51%   ▸
  ChatGPT (100%)             ▸
  Gemini CLI #1 (100%)       ▸
─────────────────────────────
Predicted EOM: $451
─────────────────────────────
Refresh (⌘R)
Check for Updates... (⌘U)
Settings... (⌘,)
Share Usage Snapshot...
─────────────────────────────
UsageBar v0.2.0
Quit (⌘Q)
```

### 🔌 Zero-Config Provider Discovery

UsageBar automatically finds and authenticates with your AI providers:

- **OpenCode auth** — Primary source (`auth.json` with XDG multi-path fallback)
- **Standalone tools** — Codex CLI, Claude Code CLI, GitHub CLI, GitHub Copilot CLI
- **macOS Keychain** — Claude, GitHub Copilot OAuth tokens
- **Editor configs** — VS Code / Cursor Copilot settings
- **Browser cookies** — Chrome, Brave, Arc, Edge (GitHub Copilot only)
- **OpenCode plugins** — Multi-account support for ChatGPT, Antigravity, Gemini, Claude
- **UsageBar-managed Codex accounts** — Add the current official `codex` login manually and keep multiple ChatGPT accounts inside UsageBar

Multi-source accounts are automatically deduplicated by email.

### 📊 13 Supported Providers

#### Pay-as-you-go

| Provider | Key Metrics |
|----------|-------------|
| **OpenRouter** | Credits balance, daily/weekly/monthly cost |
| **OpenCode** | Session-based cost summary |
| **GitHub Copilot Add-on** | Overage charges beyond included Copilot quota |

#### Quota-based

| Provider | Key Metrics |
|----------|-------------|
| **GitHub Copilot** | Multi-account, daily history, overage tracking |
| **Claude** | 5h / 7d windows, Sonnet / Opus breakdown |
| **ChatGPT** | Primary / Secondary quotas, plan type |
| **Kimi for Coding** | 5h / 7d windows, membership level |
| **Gemini CLI** | Per-model quotas, multi-account with email labels |
| **Antigravity** | Offline cache parsing (`state.vscdb`) |
| **MiniMax Coding Plan** | 5h / weekly dual-window quotas |
| **Z.AI Coding Plan** | Token / MCP quotas, tool usage (24h) |
| **Nano-GPT** | Weekly input token quota, USD / NANO balance |
| **Chutes AI** | Daily quota limits, credits balance |
| **Synthetic** | 5h usage limit, request limits |

> **Note**: ChatGPT uses the raw provider ID `codex` in CLI commands (e.g., `usagebar provider codex`).

### 📈 Usage Predictions & Pace

- **Pace indicator** — On track, slightly fast, or too fast
- **Predicted EOM** — Weighted-average estimate of end-of-month cost
- **Wait time** — Countdown until quota resets when exhausted (format: `1d 5h`, `3h`, or `45m`)

### 💰 Subscription Tracking

Set your subscription tier per provider (preset or custom monthly cost). The `Quota Status` header shows the combined monthly total, and outdated saved settings can be cleared with a localized confirmation.

### ⚙️ Settings

| Tab | Contents |
|-----|----------|
| **General** | Auto Refresh (1 min – 1 hr), Prediction Period (7 / 14 / 21 days), App Language (System / EN / 中文), Launch at Login, Critical Badge, Privacy Mode for screenshot-safe account masking, CLI Install, native-first primary action buttons |
| **Status Bar** | A lighter native macOS preview group, draggable provider ordering, per-provider visibility toggles, edge-to-edge provider cards, disabled items move to the top of the disabled group to reduce layout jumps, a concise quota-only status bar note, preview/menu order follows the Status Bar provider list, Copilot Add-on toggle |
| **Advanced Providers** | ChatGPT: save the current `codex` login into UsageBar (Keychain-backed), remove saved accounts, account selection, status bar window mode (5h / weekly / both) |
| **Subscriptions** | Native macOS menu pickers for preset plans or custom monthly cost per quota-based provider, localized outdated-setting cleanup, native-first Apply button styling, and provider icons for faster scanning |

### 🖥️ Multi-Provider Status Bar

The macOS status bar can display a compact row of quota-based provider icons with remaining percentages. Configure which providers appear via **Settings > Status Bar**. When a selected provider has a temporary fetch error, its icon stays visible with an error marker and the menu shows the error details.

### ⬇️ In-App Updates

Use **Check for Updates...** from the menu to download new GitHub Releases through Sparkle. Until UsageBar has an Apple Developer certificate, update downloads remain unsigned and may still require the Gatekeeper command shown above.

### ⌨️ CLI

A bundled command-line tool for scripting and automation:

```bash
usagebar status              # All providers (table)
usagebar status --json       # All providers (JSON)
usagebar list                # List configured providers
usagebar provider claude     # Detailed info for one provider
```

<details>
<summary>Table output example</summary>

```
$ usagebar status
Provider              Type             Usage       Key Metrics
─────────────────────────────────────────────────────────────────────────────────
Claude                Quota-based      77%         23/100 remaining
ChatGPT               Quota-based      0%          100/100 remaining
Copilot (user1)       Quota-based      45%         550/1000 remaining
Copilot (user2)       Quota-based      12%         880/1000 remaining
Gemini CLI (user@gmail.com)  Quota-based  0%       100% remaining
Kimi for Coding       Quota-based      26%         74/100 remaining
MiniMax Coding Plan   Quota-based      0%, 0%      100/100 remaining
OpenCode              Pay-as-you-go    -           $0.19 spent
OpenRouter            Pay-as-you-go    -           $37.42 spent
```

</details>

<details>
<summary>JSON output example</summary>

```json
{
  "claude": {
    "type": "quota-based",
    "remaining": 23,
    "entitlement": 100,
    "usagePercentage": 77,
    "overagePermitted": false
  },
  "copilot": {
    "type": "quota-based",
    "remaining": 1430,
    "entitlement": 2000,
    "usagePercentage": 28,
    "overagePermitted": true,
    "accounts": [
      {
        "index": 0,
        "login": "user1",
        "authSource": "opencode",
        "remaining": 550,
        "entitlement": 1000,
        "usagePercentage": 45,
        "overagePermitted": true
      }
    ]
  },
  "openrouter": {
    "type": "pay-as-you-go",
    "cost": 37.42
  }
}
```

</details>

**Exit Codes**: `0` Success · `1` General error · `2` Auth failed · `3` Network error · `4` Invalid arguments

Install the CLI from **Settings > General > Command Line Tool**, or run `bash scripts/install-cli.sh` manually.

## How It Works

1. **Token Discovery** — Reads auth tokens from OpenCode `auth.json` (XDG multi-path), Keychain, editor configs, browser cookies, and plugin metadata
2. **Account Deduplication** — Merges multi-source accounts using a stable email-first key strategy
3. **Parallel Fetching** — Queries all provider APIs simultaneously via Swift `TaskGroup` with configurable timeouts (default 30s)
4. **Smart Caching** — Falls back to cached data on network errors; daily history uses hybrid cache (fresh for recent days, cached for older)
5. **Graceful Degradation** — Shows available providers even when some fail; multi-account providers support partial success

## Privacy & Security

- **100% Local** — No data leaves your machine, no third-party analytics
- **Read-only** — Uses existing tokens only, requests no additional permissions
- **Direct API** — Queries provider APIs without intermediaries
- **Browser cookies** — GitHub Copilot optionally reads session cookies (read-only, never stored)

## Troubleshooting

<details>
<summary>"No providers found"</summary>

Verify OpenCode is installed and authenticated. The app searches for `auth.json` in:
1. `$XDG_DATA_HOME/opencode/auth.json` (if `XDG_DATA_HOME` is set)
2. `~/.local/share/opencode/auth.json` (default)
3. `~/Library/Application Support/opencode/auth.json` (macOS fallback)

For ChatGPT account discovery, the app checks (in priority order):
1. **UsageBar Codex Accounts** — Stored via **Settings → Advanced Providers → Codex → Save Current Login**
2. OpenCode auth — `auth.json` with `openai` provider entry
3. OpenCode multi-auth — `~/.opencode/auth/openai.json`
4. OpenCode legacy — `~/.opencode/openai-codex-accounts.json` and `~/.opencode/projects/*/openai-codex-accounts.json`
5. `codex-lb` — `~/.codex-lb/store.db` + `~/.codex-lb/encryption.key`
6. Official Codex login — `~/.codex/auth.json`

To keep multiple ChatGPT accounts in UsageBar, sign in with the official `codex` CLI first, then add the current account from **Settings → Advanced Providers → Codex**. UsageBar stores those accounts locally and refreshes them without changing `~/.codex/auth.json`.

</details>

<details>
<summary>GitHub Copilot not showing</summary>

Copilot accounts are discovered from (in priority order):
1. **OpenCode auth** — `copilot` entry in `auth.json`
2. **Copilot CLI Keychain** — macOS Keychain entries for `copilot-cli`
3. **GitHub CLI Keychain** — macOS Keychain entry for `gh:github.com`
4. **VS Code / Cursor** — `~/.config/github-copilot/hosts.json` and `apps.json`
5. **Browser Cookies** — Chrome, Brave, Arc, Edge session cookies

Accounts with the same login are automatically merged. Run `usagebar provider copilot` to verify detected sources.

</details>

<details>
<summary>OpenCode binary not found</summary>

The app dynamically searches for the `opencode` binary:
1. Current PATH (`which opencode`)
2. Login shell PATH
3. Common install locations: `~/.opencode/bin/opencode`, Homebrew paths, `/usr/local/bin/opencode`

</details>

## Development

### Prerequisites

- macOS 13.0+
- Xcode 15.0+

### Setup

```bash
git clone https://github.com/SHLE1/usage-bar.git
cd usage-bar
make setup    # Configure git hooks (SwiftLint + action-validator)
```

### Build & Run

```bash
# Build
xcodebuild -project UsageBar/UsageBar.xcodeproj \
  -scheme UsageBar -configuration Debug build

# Run (auto-detect build path)
open "$(xcodebuild -project UsageBar/UsageBar.xcodeproj \
  -scheme UsageBar -configuration Debug -showBuildSettings 2>/dev/null \
  | sed -n 's/^[[:space:]]*BUILT_PRODUCTS_DIR = //p' | head -n 1)/UsageBar.app"
```

Or use the VS Code task **"Debug: Kill + Build + Run"** for a one-click workflow.

### Linting

```bash
make lint            # Run all linters
make lint-swift      # SwiftLint only
make lint-actions    # GitHub Actions YAML validation only
```

## Contributing

Contributions are welcome! Please submit a Pull Request.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run `make setup` (once, after clone)
4. Make your changes and commit — pre-commit hooks run automatically
5. Push and open a Pull Request

## License

MIT License — see [LICENSE](LICENSE) for details.

## Credits

- [opgginc/opencode-bar](https://github.com/opgginc/opencode-bar)
- [ndycode/codex-multi-auth](https://github.com/ndycode/codex-multi-auth)
- [anomalyco/opencode](https://github.com/anomalyco/opencode)
- [Sparkle](https://sparkle-project.org)

---

<p align="center">
  Built for AI power users who keep one eye on usage
</p>
