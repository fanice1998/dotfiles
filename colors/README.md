# colors — 共用調色來源

這個資料夾放各色組的「單一真實來源（single source of truth）」，給各應用的佈景**手動參照**用。
這裡的檔案**不會被任何 app 直接讀取**，也不經 `scripts/link.sh` symlink；它只是調色的參考地。
要幫某個 app 套佈景時，就來這裡查 hex，貼進該 app 自己的設定格式。

目前色組：

| 檔案 | 色組 | 變體 | 來源 |
|---|---|---|---|
| [`sonokai.toml`](./sonokai.toml) | sonokai | dark | [sainnhe/sonokai](https://github.com/sainnhe/sonokai)（MIT） |

## sonokai（dark）色表

### 主要
| 用途 | 名稱 | hex |
|---|---|---|
| 主背景 | `bg0` | `#2c2e34` |
| 主前景 | `fg` | `#e2e2e3` |
| 次背景 | `bg1`–`bg5` | `#33353f` … `#444852` |
| 灰 | `grey` / `grey_dim` | `#7f8490` / `#595f6f` |

### 強調色
| 名稱 | hex | 名稱 | hex |
|---|---|---|---|
| `red` | `#fc5d7c` | `green` | `#9ed072` |
| `orange` | `#f39660` | `cyan` | `#8dd0b6` |
| `yellow` | `#e7c664` | `blue` | `#76cce0` |
| `purple` | `#b39df3` | | |

### 終端機 ANSI 16 色
背景 `#2c2e34`、前景 `#e2e2e3`、游標 `#e2e2e3`、選取 `#414550`。

| # | normal | | # | bright |
|---|---|---|---|---|
| 0 black | `#181819` | | 8 | `#7f8490` |
| 1 red | `#fc5d7c` | | 9 | `#fc5d7c` |
| 2 green | `#9ed072` | | 10 | `#9ed072` |
| 3 yellow | `#e7c664` | | 11 | `#e7c664` |
| 4 blue | `#76cce0` | | 12 | `#76cce0` |
| 5 magenta | `#b39df3` | | 13 | `#b39df3` |
| 6 cyan | `#8dd0b6` | | 14 | `#8dd0b6` |
| 7 white | `#e2e2e3` | | 15 | `#e2e2e3` |

## 怎麼套到各 app（手動參照）

各 app 的色彩設定位置與格式不同，貼值時對應上表即可：

- **rio** — `rio/config.toml.tmpl` 的 `[colors]`（`background` / `foreground` / `black`…`white` / `cursor` / `tabs` 等，hex 字串）。
- **alacritty** — `alacritty/…` 的 `[colors.primary]` + `[colors.normal]` / `[colors.bright]`。
- **ghostty** — `ghostty/config` 的 `background` / `foreground` / `palette = 0=#…`（0–15）。
- **wezterm** — `wezterm/…` 的 lua：`colors = { background, foreground, ansi = {...}, brights = {...} }`。
- **zellij / starship / fastfetch / nvim / fish** — 各自格式，取用上面的強調色即可。
- **mitos** — 已用 `mitos/themes/sonokai-transparent.toml`（`inherits = "sonokai"`，透明化版）。

> 註：目前是「手動參照」。日後若想讓 `link.sh` 從 `colors/` 自動產生各 app 佈景
> （像 rio 樣板那樣），再把這份色盤接進產生流程即可。

授權：色值來自 sonokai，原作 sainnhe，MIT 授權；詳見上游 repo。
