#!/usr/bin/env bash
# 在 macOS、Fedora、Debian / Ubuntu、Android Termux 上安裝日常套件，項目可勾選。
#
# 用法:
#   ./install-packages.sh                 方向鍵移動、空白鍵勾選、Enter 安裝
#   ./install-packages.sh --simple        改用輸入編號勾選（終端機不支援方向鍵時）
#   ./install-packages.sh --list          列出項目與這個平台的安裝方式
#   ./install-packages.sh --default       只裝預設項目
#   ./install-packages.sh --all           安裝這個平台有的全部項目
#   ./install-packages.sh fzf eza fish    只裝指定 id
#   ./install-packages.sh --dry-run --default
#   ./install-packages.sh --force go      已安裝的也重裝
#
# Bash 3.2（macOS /bin/bash）可用。
# 新增項目時改下面的 CATALOG。欄位用 | 分隔:
#   id|群組|預設(1/0)|檢查的指令|mac|fedora|debian|termux|說明
# debian 欄給 Debian、Ubuntu，以及 ID_LIKE 是它們的發行版（Linux Mint、Pop!_OS…）。
# 預設不含 lazygit、alacritty、fish、fisher、python、go、rust、node、make、cmake。
# 平台欄位:
#   套件名稱（可多個，空白分隔）
#   cask:名稱     只給 macOS，走 brew install --cask
#   -             這個平台用腳本裡的專用安裝（rustup、nvm、官方二進位…）
#                 Debian 上 eza、fastfetch、lazygit 是 apt 有就用 apt，沒有才抓 GitHub 版本
#   none          這個平台不裝

set -euo pipefail

NODE_MAJOR="${NODE_MAJOR:-24}"
NVM_VERSION="${NVM_VERSION:-v0.40.8}"

DRY_RUN=0
FORCE=0
SIMPLE=0
TOUCHED_RC=0

script_dir() {
  cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

SCRIPT_DIR="$(script_dir)"

have() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf '警告: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

is_termux() {
  if [ -n "${TERMUX_VERSION:-}" ]; then
    return 0
  fi
  if [ -n "${PREFIX:-}" ] && [ -x "${PREFIX}/bin/pkg" ]; then
    return 0
  fi
  have termux-info && return 0
  return 1
}

# Debian、Ubuntu，或 ID_LIKE 是它們的發行版。
is_debian() {
  [ -f /etc/os-release ] || return 1
  grep -qE '^(ID|ID_LIKE)="?([a-z_]+ )*(debian|ubuntu)( |"|$)' /etc/os-release
}

is_fedora() {
  if [ -f /etc/fedora-release ]; then
    return 0
  fi
  if [ -f /etc/os-release ] && grep -q '^ID=fedora$' /etc/os-release; then
    return 0
  fi
  return 1
}

# termux | macos | fedora | debian
# Termux 的 uname 是 Linux，要先判斷。
os_kind() {
  if [ -n "${OS_KIND:-}" ]; then
    case "$OS_KIND" in
      macos | fedora | debian | termux)
        printf '%s\n' "$OS_KIND"
        return 0
        ;;
      ubuntu)
        printf 'debian\n'
        return 0
        ;;
      *)
        die "OS_KIND 只能是 macos、fedora、debian（ubuntu）、termux"
        ;;
    esac
  fi
  if is_termux; then
    OS_KIND=termux
  else
    case "$(uname -s 2>/dev/null || echo unknown)" in
      Darwin) OS_KIND=macos ;;
      Linux)
        if is_fedora; then
          OS_KIND=fedora
        elif is_debian; then
          OS_KIND=debian
        else
          die "只支援 macOS、Fedora、Debian / Ubuntu、Android Termux"
        fi
        ;;
      *)
        die "只支援 macOS、Fedora、Debian / Ubuntu、Android Termux（目前是 $(uname -s 2>/dev/null || echo unknown)）"
        ;;
    esac
  fi
  printf '%s\n' "$OS_KIND"
}

CATALOG="$(
  cat <<'EOF'
git|base|1|git|git|git|git|git|版本控制
curl|base|1|curl|curl|curl|curl|curl|下載檔案
wget|base|1|wget|wget|wget|wget|wget|另一個下載工具
unzip|base|1|unzip|unzip|unzip|unzip|unzip|解 zip
rsync|base|0|rsync|rsync|rsync|rsync|rsync|同步檔案
zsh|shell|1|zsh|zsh|zsh|zsh|zsh|目前使用的 shell
fish|shell|0|fish|fish|fish|fish|fish|另一個 shell（repo 裡有設定）
fisher|shell|0|fisher|-|-|-|-|fish 外掛管理，並裝好 fish_plugins 列的外掛
fzf|shell|1|fzf|fzf|fzf|fzf|fzf|模糊搜尋（主題選單、fzf-tab）
starship|shell|1|starship|starship|-|-|starship|跨 shell 提示字元
eza|files|1|eza|eza|eza|-|eza|取代 ls（fish 的 ls alias）
trash|files|1|trash|trash-cli|trash-cli|trash-cli|-|可復原的刪除（fish 的 rm alias）
ripgrep|files|1|rg|ripgrep|ripgrep|ripgrep|ripgrep|快速搜尋檔案內容
fd|files|1|fd|fd|fd-find|fd-find|fd|快速找檔案
bat|files|1|bat|bat|bat|bat|bat|帶語法高亮的 cat
jq|files|1|jq|jq|jq|jq|jq|處理 JSON
neovim|edit|1|nvim|neovim|neovim|-|neovim|編輯器（EDITOR=nvim）
mitos|edit|0|ms|-|-|-|none|編輯器 Mitos（Helix fork，官方 installer 裝 ms）
zellij|edit|1|zellij|zellij|-|-|zellij|終端機工作區
fastfetch|edit|1|fastfetch|fastfetch|fastfetch|-|fastfetch|系統資訊
lazygit|edit|0|lazygit|lazygit|lazygit|-|lazygit|git 的終端介面
alacritty|edit|0|alacritty|cask:alacritty|alacritty|alacritty|none|終端機（repo 裡有設定）
python|lang|0|python3|python|python3 python3-pip|python3 python3-pip python3-venv|python python-pip|Python 3 與 pip
go|lang|0|go|go|-|-|golang|Go（Linux 走 scripts/install_go.sh）
rust|lang|0|rustc|-|-|-|rust|Rust（macOS / Linux 用 rustup）
node|lang|0|node|node|-|-|nodejs|Node.js（Linux 用 nvm）
make|build|0|make|-|make|make|make|編譯用 make
cmake|build|0|cmake|cmake|cmake|cmake|cmake|編譯用 cmake
compiler|build|0|cc|-|gcc gcc-c++|build-essential|clang|C/C++ 編譯器
pkg-config|build|0|pkg-config|pkg-config|pkgconf-pkg-config|pkg-config|pkg-config|編譯時找函式庫
EOF
)"

IDS=()
CATS=()
RECS=()
CMDS=()
MACS=()
FEDORAS=()
DEBIANS=()
TERMUXS=()
DESCS=()
SELECTED=()
# 每項的狀態: installed | missing | none（這個平台沒有）。畫選單時用，避免每次重畫都去檢查。
STATE=()

# fisher 自己有裝好、而且 fish_plugins 列的外掛都已由 fisher 管理，才算裝好。
FISHER_CHECK='
functions -q fisher; or exit 1
set -l have (string lower -- $_fisher_plugins)
contains jorgebucaran/fisher $have; or exit 1
test -e $__fish_config_dir/fish_plugins; or exit 0
for p in (string match -rv "^\s*(#.*)?\$" <$__fish_config_dir/fish_plugins | string trim | string lower)
    contains -- $p $have; or exit 1
end'

# 先裝 fisher，再逐一安裝 fish_plugins 列的外掛。
# 從 dotfile 複製過來的外掛檔案沒有 fisher 的紀錄，fisher 會回報 conflicting files 而不安裝。
# 碰到這種情況就把那些檔案移到備份目錄，再裝一次，讓 fisher 接手管理。
FISHER_INSTALL='
set -l dir $__fish_config_dir
if not functions -q fisher
    curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
    or begin
        echo "fisher: 下載失敗" >&2
        exit 1
    end
end
set -l want jorgebucaran/fisher
if test -e $dir/fish_plugins
    for p in (string match -rv "^\s*(#.*)?\$" <$dir/fish_plugins | string trim)
        contains -- (string lower -- $p) (string lower -- $want); or set -a want $p
    end
end
set -l bak $dir/fisher-backup-(date +%Y%m%d%H%M%S)
set -l failed
set -l before (string lower -- $_fisher_plugins)
for p in $want
    # 新裝的 fisher 會順手裝好 fish_plugins 列的外掛，這次才裝上的就不必再裝一次。
    set -l lp (string lower -- $p)
    if not contains -- $lp $before; and contains -- $lp (string lower -- $_fisher_plugins)
        continue
    end
    set -l out (fisher install $p 2>&1)
    printf "%s\n" $out
    string match -q "*Cannot install*" -- $out; or continue
    for f in (string match -rg "^\s+(/.+)\$" -- $out)
        set -l dest $bak/(string replace -- "$dir/" "" $f)
        mkdir -p (dirname $dest); and mv $f $dest
    end
    echo "==> 原本的檔案移到 $bak，重新安裝 $p"
    set out (fisher install $p 2>&1)
    printf "%s\n" $out
    string match -q "*Cannot install*" -- $out; and set -a failed $p
end
if set -q failed[1]
    echo "fisher: 這些外掛沒有裝好: $failed" >&2
    exit 1
end'

load_catalog() {
  local id group rec cmd mac fed deb tx desc
  # read 在最後一行沒有換行時會回傳失敗，但仍有讀到內容。清掉 id，避免 EOF 時重複最後一筆。
  while IFS='|' read -r id group rec cmd mac fed deb tx desc || [ -n "${id:-}" ]; do
    [ -n "${id:-}" ] || continue
    case "$id" in
      \#*) id="" ; continue ;;
    esac
    IDS+=("$id")
    CATS+=("$group")
    RECS+=("$rec")
    CMDS+=("$cmd")
    MACS+=("$mac")
    FEDORAS+=("$fed")
    DEBIANS+=("$deb")
    TERMUXS+=("$tx")
    DESCS+=("$desc")
    SELECTED+=(0)
    id=""
  done <<EOF
$CATALOG
EOF
}

group_name() {
  case "$1" in
    base) printf '基礎\n' ;;
    shell) printf 'Shell\n' ;;
    files) printf '檔案與搜尋\n' ;;
    edit) printf '編輯器與終端\n' ;;
    lang) printf '語言\n' ;;
    build) printf '編譯\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

spec_at() {
  local i="$1"
  case "$OS" in
    macos) printf '%s\n' "${MACS[$i]}" ;;
    fedora) printf '%s\n' "${FEDORAS[$i]}" ;;
    debian) printf '%s\n' "${DEBIANS[$i]}" ;;
    termux) printf '%s\n' "${TERMUXS[$i]}" ;;
  esac
}

is_available() {
  local spec
  spec="$(spec_at "$1")"
  [ -n "$spec" ] && [ "$spec" != "none" ]
}

is_installed() {
  local i="$1"
  case "${IDS[$i]}" in
    python)
      have python3 && { have pip || have pip3; }
      ;;
    rust)
      have rustc && have cargo
      ;;
    compiler)
      have gcc || have clang || have cc
      ;;
    pkg-config)
      have pkg-config || have pkgconf
      ;;
    fisher)
      # 一般啟動才會讀 universal 變數與 functions 目錄；config.fish 的錯誤訊息不要印出來。
      have fish && fish -c "$FISHER_CHECK" >/dev/null 2>&1
      ;;
    *)
      have "${CMDS[$i]}"
      ;;
  esac
}

refresh_states() {
  local i
  for i in "${!IDS[@]}"; do
    if ! is_available "$i"; then
      STATE[$i]=none
    elif is_installed "$i"; then
      STATE[$i]=installed
    else
      STATE[$i]=missing
    fi
  done
}

state_label() {
  case "${STATE[$1]}" in
    none) printf '不支援\n' ;;
    installed) printf '已安裝\n' ;;
    *) printf '未安裝\n' ;;
  esac
}

special_label() {
  local id="$1"
  case "$OS:$id" in
    fedora:starship | debian:starship) printf '%s\n' "官方安裝腳本 → ~/.local/bin" ;;
    fedora:zellij | debian:zellij) printf '%s\n' "GitHub 最新版 → ~/.local/bin" ;;
    debian:neovim) printf '%s\n' "GitHub 最新版 → ~/.local/opt/nvim（apt 版本太舊）" ;;
    macos:mitos | fedora:mitos | debian:mitos) printf '%s\n' "官方 installer（mitos.computer）→ ms" ;;
    debian:eza | debian:fastfetch | debian:lazygit) printf '%s\n' "apt 有就用 apt，沒有用 GitHub 最新版" ;;
    fedora:go | debian:go) printf '%s\n' "scripts/install_go.sh" ;;
    macos:rust | fedora:rust | debian:rust) printf '%s\n' "rustup" ;;
    fedora:node | debian:node) printf '%s\n' "nvm install ${NODE_MAJOR}" ;;
    macos:compiler | macos:make) printf '%s\n' "xcode-select --install" ;;
    termux:trash) printf '%s\n' "pip install trash-cli" ;;
    *:fisher) printf '%s\n' "官方 fisher.fish，再 fisher install fish_plugins" ;;
    *) printf '%s\n' "專用安裝" ;;
  esac
}

method_label() {
  local i="$1" spec
  spec="$(spec_at "$i")"
  case "$spec" in
    none) printf '%s\n' "（沒有）" ;;
    -) special_label "${IDS[$i]}" ;;
    cask:*) printf '%s\n' "brew --cask ${spec#cask:}" ;;
    *) printf '%s\n' "$spec" ;;
  esac
}

usage() {
  cat <<EOF
在 macOS、Fedora、Debian / Ubuntu、Android Termux 安裝日常套件。每次只裝你選的項目。

用法:
  ./install-packages.sh                 自己選要裝哪些（方向鍵 + 空白鍵）
  ./install-packages.sh --simple        改用輸入編號勾選
  ./install-packages.sh --list          列出 id、狀態、這個平台的裝法
  ./install-packages.sh --default       只裝預設項目裡還沒裝的
  ./install-packages.sh --all           安裝這個平台支援、且還沒裝的全部項目
  ./install-packages.sh fzf eza fish    只裝這些 id
  ./install-packages.sh --dry-run fish  只印出會執行的指令
  ./install-packages.sh --force go      已安裝的也重做

不帶參數時開啟勾選清單，一開始已勾好「預設項目裡還沒裝的」，直接按 Enter 就能裝。
  ↑ ↓ / j k   移動
  空白 / x    勾選或取消
  a           改勾預設項目裡還沒裝的
  A           勾這個平台有的全部項目
  n           清空
  Enter       開始安裝
  q / Esc     取消
  已安裝又被勾到時會略過。要重裝請加上 --force。

--simple（或終端機不支援時）改用輸入編號:
  7 20 22     同時切換這三個（也可以用逗號分開）
  3-9         勾起 3 到 9
  fish go     也可以打 id
  a / A / n   同上
  d           開始安裝
  q           取消

預設（--default，或清單裡按 a）不含:
  lazygit、alacritty、fish、fisher、python、go、rust、node、make、cmake
  另外也不含 rsync、compiler、pkg-config。這些在清單裡照樣可以勾。

平台:
  macOS    Homebrew（Alacritty 用 cask）。沒有 brew 會停下並附上安裝網址。
  Fedora   sudo dnf install。starship / zellij / Go / Rust / Node 用下面的方式。
  Debian   sudo apt-get install（含 Ubuntu 與衍生版）。fd、bat 的指令名稱是 fdfind、batcat，
           會在 ~/.local/bin 補上 fd、bat 連結。
  Termux   pkg install。trash 改走 pip。

跟套件庫不同步、所以另外處理的項目:
  starship   Fedora / Debian：官方腳本裝到 ~/.local/bin
  zellij     Fedora / Debian：GitHub 最新版（發行版套件較舊或沒有）裝到 ~/.local/bin
  neovim     Debian：GitHub 最新版裝到 ~/.local/opt/nvim（apt 版本低於 LazyVim 要求的 0.11）
  mitos      各平台：官方 installer（curl mitos.computer/install.sh）裝 ms（Helix fork）
  eza        Debian：apt 有就用 apt（Debian 13、Ubuntu 24.04），沒有用 GitHub 最新版
  fastfetch  Debian：apt 有就用 apt，沒有用 GitHub 的 .deb
  lazygit    Debian：apt 有就用 apt，沒有用 GitHub 最新版
  go         Fedora / Debian：scripts/install_go.sh（官方 tarball）。Mac brew、Termux golang
  rust       macOS / Fedora / Debian：rustup。Termux：pkg install rust
  node       Fedora / Debian：nvm 安裝 Node ${NODE_MAJOR}。Mac brew、Termux nodejs
  compiler   macOS：Xcode Command Line Tools。Fedora gcc、Debian build-essential、Termux clang
  fisher     各平台：官方 fisher.fish，再裝 fish_plugins 列的外掛。沒有 fish 會一併裝。
             設定目錄裡已有、但不是 fisher 裝的外掛檔案，會先移到 fisher-backup-*/ 再重裝

Zellij 狀態列插件請用 ../zellij/install.sh。

環境變數:
  OS_KIND      覆寫平台偵測（macos、fedora、debian、termux），用來預覽別的平台
  NODE_MAJOR   Fedora 上 nvm 要裝的 Node 主版本（預設 ${NODE_MAJOR}）
  NVM_VERSION  nvm 版本（預設 ${NVM_VERSION}）
EOF
}

list_catalog() {
  local i rec state
  printf '平台: %s (%s)\n\n' "$OS" "$(uname -m 2>/dev/null || echo unknown)"
  printf '%-12s %-6s %-8s %s\n' "ID" "預設" "狀態" "這個平台"
  printf '%-12s %-6s %-8s %s\n' "------------" "------" "--------" "----------"
  for i in "${!IDS[@]}"; do
    if [ "${RECS[$i]}" = "1" ]; then
      rec="是"
    else
      rec="-"
    fi
    state="$(state_label "$i")"
    printf '%-12s %-6s %-8s %s\n' "${IDS[$i]}" "$rec" "$state" "$(method_label "$i")"
    printf '%-12s %-6s %-8s %s\n' "" "" "" "${DESCS[$i]}"
  done
}

# ---- 方向鍵勾選清單 ----

TUI_ROWS=()
TUI_TOP=0
TUI_MSG=""

tui_supported() {
  [ -r /dev/tty ] && [ -w /dev/tty ] || return 1
  case "${TERM:-dumb}" in
    dumb | '') return 1 ;;
  esac
  stty -g </dev/tty >/dev/null 2>&1
}

term_lines() {
  local size
  size="$(stty size </dev/tty 2>/dev/null)" || size=""
  size="${size%% *}"
  case "$size" in
    '' | *[!0-9]*) size="${LINES:-24}" ;;
  esac
  printf '%s\n' "$size"
}

# 清單的每一列：群組標題是 "g:群組"，項目是 IDS 的索引。
tui_build_rows() {
  local i last=""
  TUI_ROWS=()
  for i in "${!IDS[@]}"; do
    if [ "${CATS[$i]}" != "$last" ]; then
      last="${CATS[$i]}"
      TUI_ROWS+=("g:$last")
    fi
    TUI_ROWS+=("$i")
  done
}

# 從 row 往 step 方向找下一個項目列；找不到就留在原地。
tui_step() {
  local row="$1" step="$2" n="${#TUI_ROWS[@]}"
  local r=$((row + step))
  while [ "$r" -ge 0 ] && [ "$r" -lt "$n" ]; do
    case "${TUI_ROWS[$r]}" in
      g:*) r=$((r + step)) ;;
      *)
        printf '%s\n' "$r"
        return 0
        ;;
    esac
  done
  printf '%s\n' "$row"
}

tui_draw() {
  local cur="$1" lines view n r end row i mark rec state color pointer hl out count=0 picked=""
  local esc=$'\033'
  lines="$(term_lines)"
  n="${#TUI_ROWS[@]}"
  view=$((lines - 5))
  [ "$view" -ge 3 ] || view=3
  # 游標要在畫面內。往上捲時多露出一列，讓群組標題看得到。
  if [ "$cur" -le "$TUI_TOP" ]; then
    TUI_TOP=$((cur - 1))
    [ "$TUI_TOP" -ge 0 ] || TUI_TOP=0
  elif [ "$cur" -ge $((TUI_TOP + view)) ]; then
    TUI_TOP=$((cur - view + 1))
  fi
  end=$((TUI_TOP + view))
  [ "$end" -le "$n" ] || end="$n"

  for i in "${!IDS[@]}"; do
    if [ "${SELECTED[$i]}" = "1" ]; then
      count=$((count + 1))
      picked="$picked ${IDS[$i]}"
    fi
  done

  out="${esc}[H${esc}[1m選擇要安裝的套件${esc}[0m  平台 $OS  ${esc}[2m* 是預設項目${esc}[0m${esc}[K"$'\n'
  out="$out${esc}[2m↑↓/jk 移動  空白 勾選  a 預設  A 全部  n 清空  Enter 安裝  q 離開${esc}[0m${esc}[K"$'\n'
  r="$TUI_TOP"
  while [ "$r" -lt "$end" ]; do
    row="${TUI_ROWS[$r]}"
    case "$row" in
      g:*)
        out="$out${esc}[1;36m$(group_name "${row#g:}")${esc}[0m${esc}[K"$'\n'
        ;;
      *)
        i="$row"
        if [ "${SELECTED[$i]}" = "1" ]; then mark="x"; else mark=" "; fi
        if [ "${RECS[$i]}" = "1" ]; then rec="*"; else rec=" "; fi
        state="$(state_label "$i")"
        case "${STATE[$i]}" in
          installed) color="${esc}[32m" ;;
          none) color="${esc}[2m" ;;
          *) color="" ;;
        esac
        # 游標所在列反白；狀態的顏色會重設樣式，所以後面要再開一次反白。
        if [ "$r" -eq "$cur" ]; then
          pointer=">"
          hl="${esc}[7m"
        else
          pointer=" "
          hl=""
        fi
        out="$out$hl$(printf ' %s [%s] %s %-11s ' "$pointer" "$mark" "$rec" "${IDS[$i]}")"
        out="$out$color$state${esc}[0m$hl  ${DESCS[$i]}${esc}[0m${esc}[K"$'\n'
        ;;
    esac
    r=$((r + 1))
  done
  [ "$picked" ] || picked=" （還沒有）"
  out="$out${esc}[K"$'\n'"已勾 $count 項:$picked${esc}[K"$'\n'
  out="$out${esc}[33m$TUI_MSG${esc}[0m${esc}[K${esc}[J"
  printf '%s' "$out"
}

tui_enter() {
  # 切到替代畫面、隱藏游標、關掉自動換行（窄螢幕不會把一列擠成兩列）。
  printf '\033[?1049h\033[?25l\033[?7l' >/dev/tty
  trap 'tui_leave' EXIT
  trap 'tui_leave; exit 130' INT TERM
}

tui_leave() {
  printf '\033[?7h\033[?25h\033[?1049l' >/dev/tty
}

tui_toggle() {
  local i="$1"
  case "${STATE[$i]}" in
    none)
      TUI_MSG="${IDS[$i]} 在 $OS 沒有安裝方式"
      return 0
      ;;
  esac
  if [ "${SELECTED[$i]}" = "1" ]; then
    SELECTED[$i]=0
  else
    SELECTED[$i]=1
    if [ "${STATE[$i]}" = "installed" ] && [ "$FORCE" -eq 0 ]; then
      TUI_MSG="${IDS[$i]} 已安裝，會略過。要重裝請加 --force"
    fi
  fi
}

tui_select() {
  local cur key rest act i any
  tui_build_rows
  cur="$(tui_step -1 1)"
  TUI_TOP=0
  tui_enter
  while true; do
    tui_draw "$cur" >/dev/tty
    TUI_MSG=""
    key=""
    IFS= read -rsn1 key </dev/tty || key=q
    act=""
    case "$key" in
      $'\033')
        rest=""
        IFS= read -rsn2 -t 1 rest </dev/tty || true
        case "$rest" in
          '[A' | 'OA') act=up ;;
          '[B' | 'OB') act=down ;;
          '') act=quit ;;
        esac
        ;;
      k) act=up ;;
      j) act=down ;;
      ' ' | x) act=toggle ;;
      a) select_missing_recommended ;;
      A) select_all ;;
      n) select_none ;;
      '') act=done ;;
      q | Q) act=quit ;;
    esac
    case "$act" in
      up) cur="$(tui_step "$cur" -1)" ;;
      down) cur="$(tui_step "$cur" 1)" ;;
      toggle) tui_toggle "${TUI_ROWS[$cur]}" ;;
      done)
        any=0
        for i in "${!IDS[@]}"; do
          [ "${SELECTED[$i]}" = "1" ] && any=1
        done
        if [ "$any" -eq 1 ]; then
          break
        fi
        TUI_MSG="還沒勾任何項目。用空白鍵勾選，或按 q 離開"
        ;;
      quit)
        tui_leave
        trap - EXIT INT TERM
        printf '已取消\n'
        exit 0
        ;;
    esac
  done
  tui_leave
  trap - EXIT INT TERM
  print_checked
}

# ---- 輸入編號勾選（--simple，或終端機不支援方向鍵時） ----

draw_menu() {
  local i mark recmark last_group=""
  printf '\n平台: %s (%s)\n' "$OS" "$(uname -m 2>/dev/null || echo unknown)"
  printf '星號是預設項目。現在勾到的才會裝。已安裝的勾了也會略過，要重裝請加 --force。\n'
  for i in "${!IDS[@]}"; do
    if [ "${CATS[$i]}" != "$last_group" ]; then
      last_group="${CATS[$i]}"
      printf '\n%s\n' "$(group_name "$last_group")"
    fi
    if [ "${SELECTED[$i]}" = "1" ]; then
      mark="x"
    else
      mark=" "
    fi
    if [ "${RECS[$i]}" = "1" ]; then
      recmark="*"
    else
      recmark=" "
    fi
    printf '  %2d [%s] %s %-11s %s  %s\n' \
      "$((i + 1))" "$mark" "$recmark" "${IDS[$i]}" "$(state_label "$i")" "${DESCS[$i]}"
  done
  printf '\n'
  print_checked
  printf '輸入編號切換勾選，例如 7 20 22；3-9 勾起一段；也可以打 id\n'
  printf 'd 開始安裝  q 取消  a 改勾預設  A 全部  n 清空\n'
}

print_checked() {
  local i any=0
  printf '目前勾選:'
  for i in "${!IDS[@]}"; do
    if [ "${SELECTED[$i]}" = "1" ]; then
      printf ' %s' "${IDS[$i]}"
      any=1
    fi
  done
  if [ "$any" -eq 0 ]; then
    printf ' （還沒有）'
  fi
  printf '\n'
}

read_line() {
  local value=""
  if [ -r /dev/tty ]; then
    IFS= read -r value </dev/tty || return 1
  else
    IFS= read -r value || return 1
  fi
  printf '%s\n' "$value"
}

can_prompt() {
  [ -t 0 ] || [ -r /dev/tty ]
}

select_none() {
  local i
  for i in "${!IDS[@]}"; do
    SELECTED[$i]=0
  done
}

select_recommended() {
  local i
  select_none
  for i in "${!IDS[@]}"; do
    if [ "${RECS[$i]}" = "1" ] && is_available "$i"; then
      SELECTED[$i]=1
    fi
  done
}

select_all() {
  local i
  select_none
  for i in "${!IDS[@]}"; do
    if [ "${STATE[$i]}" != "none" ]; then
      SELECTED[$i]=1
    fi
  done
}

select_missing_recommended() {
  local i
  select_none
  for i in "${!IDS[@]}"; do
    if [ "${RECS[$i]}" = "1" ] && [ "${STATE[$i]}" = "missing" ]; then
      SELECTED[$i]=1
    fi
  done
}

toggle_index() {
  local i="$1"
  if [ "$i" -lt 0 ] || [ "$i" -ge "${#IDS[@]}" ]; then
    warn "沒有編號 $((i + 1))"
    return 0
  fi
  if [ "${STATE[$i]}" = "none" ]; then
    warn "${IDS[$i]} 在 $OS 沒有對應安裝方式"
    return 0
  fi
  if [ "${SELECTED[$i]}" = "1" ]; then
    SELECTED[$i]=0
  else
    SELECTED[$i]=1
  fi
}

# 3-9 這種範圍一律勾起（不是切換），這個平台沒有的項目直接跳過。
select_range() {
  local lo="$1" hi="$2" n
  if [ "$lo" -gt "$hi" ]; then
    n="$lo"
    lo="$hi"
    hi="$n"
  fi
  for ((n = lo; n <= hi; n++)); do
    if [ "$n" -ge 1 ] && [ "$n" -le "${#IDS[@]}" ] && [ "${STATE[$((n - 1))]}" != "none" ]; then
      SELECTED[$((n - 1))]=1
    fi
  done
}

toggle_token() {
  local tok="$1" i
  case "$tok" in
    [0-9]*-[0-9]*)
      case "${tok%-*}${tok#*-}" in
        *[!0-9]*) warn "看不懂的範圍: $tok" ;;
        *) select_range "${tok%-*}" "${tok#*-}" ;;
      esac
      ;;
    '' | *[!0-9]*)
      if ! i="$(index_of "$tok")"; then
        warn "沒有這個項目: $tok"
        return 0
      fi
      toggle_index "$i"
      ;;
    *)
      toggle_index "$((tok - 1))"
      ;;
  esac
}

number_select() {
  local line tok
  while true; do
    draw_menu
    printf '> '
    line="$(read_line)" || exit 0
    line=${line//,/ }
    [ -n "$line" ] || continue
    set -f
    for tok in $line; do
      case "$tok" in
        a) select_missing_recommended ;;
        A) select_all ;;
        n) select_none ;;
        d)
          set +f
          return 0
          ;;
        q | quit | exit)
          set +f
          printf '已取消\n'
          exit 0
          ;;
        *) toggle_token "$tok" ;;
      esac
    done
    set +f
  done
}

interactive_menu() {
  refresh_states
  # 一開始就勾好「預設項目裡還沒裝的」，大多數時候直接確認就好。
  select_missing_recommended
  if [ "$SIMPLE" -eq 0 ] && tui_supported; then
    tui_select
  else
    number_select
  fi
}

index_of() {
  local name="$1" i
  for i in "${!IDS[@]}"; do
    if [ "${IDS[$i]}" = "$name" ]; then
      printf '%s\n' "$i"
      return 0
    fi
  done
  return 1
}

select_names() {
  local name i
  select_none
  for name in "$@"; do
    if ! i="$(index_of "$name")"; then
      die "未知套件: $name（見 --list）"
    fi
    if ! is_available "$i"; then
      die "${name} 在 $OS 沒有對應安裝方式"
    fi
    SELECTED[$i]=1
  done
}

FORMULAS=()
CASKS=()
DNF_PKGS=()
APT_PKGS=()
TERMUX_PKGS=()
SPECIAL_IDX=()
SEEN_TOKENS=" "
QUEUED=0
SKIPPED=0
XCODE_DONE=0
APT_UPDATED=0

add_token() {
  local token="$1"
  case " $SEEN_TOKENS " in
    *" $token "*) return 0 ;;
  esac
  SEEN_TOKENS="$SEEN_TOKENS$token "
  case "$OS" in
    macos)
      case "$token" in
        cask:*) CASKS+=("${token#cask:}") ;;
        *) FORMULAS+=("$token") ;;
      esac
      ;;
    fedora) DNF_PKGS+=("$token") ;;
    debian) APT_PKGS+=("$token") ;;
    termux) TERMUX_PKGS+=("$token") ;;
  esac
}

queue_index() {
  local i="$1" spec token
  if ! is_available "$i"; then
    return 0
  fi
  if [ "$FORCE" -eq 0 ] && is_installed "$i"; then
    log "已安裝 ${IDS[$i]}，略過"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi
  spec="$(spec_at "$i")"
  if [ "$spec" = "-" ]; then
    SPECIAL_IDX+=("$i")
    QUEUED=$((QUEUED + 1))
    return 0
  fi
  for token in $spec; do
    add_token "$token"
  done
  QUEUED=$((QUEUED + 1))
}

# 專用安裝需要、但這台還沒有的套件，排進套件管理器那一批一起裝。
queue_dep() {
  local dep="$1" why="$2" dep_i spec token
  have "$dep" && return 0
  dep_i="$(index_of "$dep")" || die "需要 $dep，但清單裡沒有 $dep"
  spec="$(spec_at "$dep_i")"
  [ "$spec" != "-" ] && [ "$spec" != "none" ] || die "需要 $dep，但 $OS 沒有 $dep 套件"
  log "${why}，一併加入 $dep"
  for token in $spec; do
    add_token "$token"
  done
}

ensure_deps_for_specials() {
  local sidx id need_curl=0 need_fish=0
  [ "${#SPECIAL_IDX[@]}" -gt 0 ] || return 0
  for sidx in "${SPECIAL_IDX[@]}"; do
    id="${IDS[$sidx]}"
    case "$id" in
      starship | zellij | neovim | eza | fastfetch | lazygit | go | rust | node | mitos) need_curl=1 ;;
      fisher)
        need_curl=1
        need_fish=1
        ;;
    esac
  done
  [ "$need_curl" -eq 0 ] || queue_dep curl "下載安裝需要 curl"
  [ "$need_fish" -eq 0 ] || queue_dep fish "fisher 需要 fish"
}

apt_update_once() {
  [ "$APT_UPDATED" -eq 0 ] || return 0
  APT_UPDATED=1
  log "$(root_prefix)apt-get update"
  if [ "$DRY_RUN" -eq 0 ]; then
    as_root apt-get update
  fi
}

apt_install() {
  apt_update_once
  log "$(root_prefix)apt-get install -y $*"
  if [ "$DRY_RUN" -eq 0 ]; then
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
  fi
}

# apt 套件庫有這個套件才回傳成功。
# 先存起來再比對：直接接 grep -q 會提早關掉管線，apt-cache 收到 SIGPIPE，pipefail 就當成失敗。
apt_has() {
  local policy
  apt_update_once
  policy="$(apt-cache policy "$1" 2>/dev/null)" || return 1
  case "$policy" in
    *"Candidate: ("*) return 1 ;;
    *"Candidate: "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Debian 的 fd、bat 指令叫 fdfind、batcat。這次有裝它們、又沒有 fd、bat 時，補上連結。
link_debian_names() {
  local pair want real pkg
  for pair in fd:fdfind:fd-find bat:batcat:bat; do
    IFS=: read -r want real pkg <<EOF
$pair
EOF
    have "$want" && continue
    case " ${APT_PKGS[*]} " in
      *" $pkg "*) ;;
      *) continue ;;
    esac
    ensure_local_bin
    if [ "$DRY_RUN" -eq 1 ]; then
      log "dry-run: ln -s $real ~/.local/bin/$want"
      continue
    fi
    have "$real" || continue
    ln -sf "$(command -v "$real")" "$HOME/.local/bin/$want"
    log "已連結 ~/.local/bin/$want → $real"
  done
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    if ! have sudo; then
      die "需要 sudo 才能安裝系統套件"
    fi
    sudo "$@"
  fi
}

root_prefix() {
  if [ "$(id -u)" -eq 0 ]; then
    printf ''
  else
    printf 'sudo '
  fi
}

run_pkg_plan() {
  local kind
  kind="$OS"
  case "$kind" in
    macos)
      if [ "${#FORMULAS[@]}" -eq 0 ] && [ "${#CASKS[@]}" -eq 0 ]; then
        return 0
      fi
      if [ "$DRY_RUN" -eq 0 ] && ! have brew; then
        die "找不到 Homebrew。先安裝 https://brew.sh 再執行這個腳本"
      fi
      if [ "${#FORMULAS[@]}" -gt 0 ]; then
        log "brew install ${FORMULAS[*]}"
        if [ "$DRY_RUN" -eq 0 ]; then
          brew install "${FORMULAS[@]}"
        fi
      fi
      if [ "${#CASKS[@]}" -gt 0 ]; then
        log "brew install --cask ${CASKS[*]}"
        if [ "$DRY_RUN" -eq 0 ]; then
          brew install --cask "${CASKS[@]}"
        fi
      fi
      ;;
    fedora)
      if [ "${#DNF_PKGS[@]}" -eq 0 ]; then
        return 0
      fi
      log "$(root_prefix)dnf install -y ${DNF_PKGS[*]}"
      if [ "$DRY_RUN" -eq 0 ]; then
        as_root dnf install -y "${DNF_PKGS[@]}"
      fi
      ;;
    debian)
      if [ "${#APT_PKGS[@]}" -eq 0 ]; then
        return 0
      fi
      apt_install "${APT_PKGS[@]}"
      link_debian_names
      ;;
    termux)
      if [ "${#TERMUX_PKGS[@]}" -eq 0 ]; then
        return 0
      fi
      if [ "$DRY_RUN" -eq 0 ] && ! have pkg; then
        die "找不到 pkg"
      fi
      log "pkg install -y ${TERMUX_PKGS[*]}"
      if [ "$DRY_RUN" -eq 0 ]; then
        pkg install -y "${TERMUX_PKGS[@]}"
      fi
      ;;
  esac
}

append_rc_once() {
  local file="$1" text="$2" create="${3:-0}"
  if [ -f "$file" ] && grep -qF "$text" "$file" 2>/dev/null; then
    return 0
  fi
  if [ ! -f "$file" ] && [ "$create" -ne 1 ]; then
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: 會把設定寫進 $file"
    TOUCHED_RC=1
    return 0
  fi
  if [ ! -f "$file" ]; then
    printf '%s\n' "$text" >"$file"
  else
    printf '\n# dotfile install-packages\n%s\n' "$text" >>"$file"
  fi
  log "已寫入 $file"
  TOUCHED_RC=1
}

ensure_local_bin() {
  local line='export PATH="$HOME/.local/bin:$PATH"'
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$HOME/.local/bin"
  fi
  case ":${PATH}:" in
    *:"$HOME/.local/bin":*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
  # 已有 .local/bin 就不要再寫一行，避免和原本的 PATH 設定重複。
  if [ -f "$HOME/.zshrc" ] && grep -qF '.local/bin' "$HOME/.zshrc"; then
    :
  else
    append_rc_once "$HOME/.zshrc" "$line" 1
  fi
  if [ -f "$HOME/.bashrc" ] && grep -qF '.local/bin' "$HOME/.bashrc"; then
    :
  elif [ -f "$HOME/.bashrc" ]; then
    append_rc_once "$HOME/.bashrc" "$line" 0
  fi
}

ensure_cargo_rc() {
  local line='[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
  append_rc_once "$HOME/.zshrc" "$line"
  append_rc_once "$HOME/.bashrc" "$line"
}

ensure_nvm_rc() {
  local file block
  block='export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"'
  for file in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$file" ] && grep -q 'NVM_DIR' "$file" 2>/dev/null; then
      continue
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      log "dry-run: 會把 nvm 設定寫進 $file"
      TOUCHED_RC=1
      continue
    fi
    if [ ! -f "$file" ]; then
      printf '%s\n' "$block" >"$file"
    else
      printf '\n# dotfile install-packages\n%s\n' "$block" >>"$file"
    fi
    log "已寫入 $file"
    TOUCHED_RC=1
  done
}

install_xcode_clt() {
  if [ "$XCODE_DONE" -eq 1 ]; then
    return 0
  fi
  XCODE_DONE=1
  log "安裝 Xcode Command Line Tools（make / clang）"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: xcode-select --install"
    return 0
  fi
  if ! xcode-select --install; then
    warn "若沒有跳出安裝視窗，請在「系統設定」安裝 Command Line Tools，或再執行一次 xcode-select --install"
  fi
}

install_starship() {
  ensure_local_bin
  local -a args=(--yes --bin-dir "$HOME/.local/bin")
  if [ "$FORCE" -eq 1 ]; then
    args+=(--force)
  fi
  log "安裝 starship 到 ~/.local/bin"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: curl -fsSL https://starship.rs/install.sh | sh -s -- ${args[*]}"
    return 0
  fi
  curl -fsSL https://starship.rs/install.sh | sh -s -- "${args[@]}"
}

# Mitos 編輯器（Helix fork）。沒有發行版套件，用官方 installer，執行檔叫 ms。
install_mitos() {
  log "安裝 Mitos 編輯器（ms）"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: curl -fsSL https://mitos.computer/install.sh | sh"
    return 0
  fi
  curl -fsSL https://mitos.computer/install.sh | sh
  have ms || warn "Mitos 裝完後找不到 ms；可能要把安裝目錄加進 PATH，或開新的 shell 再試"
}

# 印出 x86_64 或 aarch64；其他架構沒有預編版本。
linux_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'x86_64\n' ;;
    aarch64 | arm64) printf 'aarch64\n' ;;
    *) return 1 ;;
  esac
}

# 下載 tar.gz，把裡面叫 name 的執行檔裝到 ~/.local/bin。
install_release_bin() {
  local name="$1" url="$2" tmp bin
  ensure_local_bin
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: curl -fL $url → ~/.local/bin/$name"
    return 0
  fi
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  curl -fL --retry 3 --retry-delay 1 -o "$tmp/release.tar.gz" "$url"
  tar -C "$tmp" -xzf "$tmp/release.tar.gz"
  bin="$(find "$tmp" -type f -name "$name" -print -quit)"
  [ -n "$bin" ] || die "壓縮檔裡找不到 $name"
  install -m 755 "$bin" "$HOME/.local/bin/$name"
  rm -rf "$tmp"
  trap - EXIT
  log "已安裝 ~/.local/bin/$name"
}

# GitHub 最新 release 的 tag，例如 v0.66.2。
github_latest_tag() {
  local url
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest")" || return 1
  printf '%s\n' "${url##*/}"
}

install_zellij_release() {
  local arch
  arch="$(linux_arch)" || die "沒有對應的 zellij 預編版本：$(uname -m)"
  log "安裝 zellij（${arch}）到 ~/.local/bin"
  install_release_bin zellij \
    "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz"
}

# 整個目錄放在 ~/.local/opt/nvim（裡面有 runtime），~/.local/bin/nvim 連過去。
install_neovim_release() {
  local arch url tmp dest="$HOME/.local/opt/nvim"
  arch="$(linux_arch)" || die "沒有對應的 neovim 預編版本：$(uname -m)"
  [ "$arch" = "aarch64" ] && arch=arm64
  url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${arch}.tar.gz"
  log "安裝 neovim（${arch}）到 ~/.local/opt/nvim"
  ensure_local_bin
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: curl -fL $url → $dest，連結 ~/.local/bin/nvim"
    return 0
  fi
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  curl -fL --retry 3 --retry-delay 1 -o "$tmp/nvim.tar.gz" "$url"
  tar -C "$tmp" -xzf "$tmp/nvim.tar.gz"
  [ -x "$tmp/nvim-linux-${arch}/bin/nvim" ] || die "壓縮檔裡找不到 nvim"
  mkdir -p "$HOME/.local/opt"
  rm -rf "$dest"
  mv "$tmp/nvim-linux-${arch}" "$dest"
  ln -sf "$dest/bin/nvim" "$HOME/.local/bin/nvim"
  rm -rf "$tmp"
  trap - EXIT
  log "已安裝 $("$HOME/.local/bin/nvim" --version 2>/dev/null | head -n 1)"
}

install_eza_debian() {
  local arch
  if apt_has eza; then
    apt_install eza
    return 0
  fi
  arch="$(linux_arch)" || die "沒有對應的 eza 預編版本：$(uname -m)"
  log "apt 沒有 eza，改裝 GitHub 最新版"
  install_release_bin eza \
    "https://github.com/eza-community/eza/releases/latest/download/eza_${arch}-unknown-linux-gnu.tar.gz"
}

install_fastfetch_debian() {
  local arch url tmp
  if apt_has fastfetch; then
    apt_install fastfetch
    return 0
  fi
  arch="$(linux_arch)" || die "沒有對應的 fastfetch 預編版本：$(uname -m)"
  [ "$arch" = "x86_64" ] && arch=amd64
  url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${arch}.deb"
  log "apt 沒有 fastfetch，改裝 GitHub 的 .deb"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: curl -fL $url，再 apt-get install 這個 .deb"
    return 0
  fi
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  curl -fL --retry 3 --retry-delay 1 -o "$tmp/fastfetch.deb" "$url"
  # apt 用 _apt 使用者讀檔，mktemp 的目錄只有自己能讀。
  chmod 755 "$tmp"
  chmod 644 "$tmp/fastfetch.deb"
  apt_install "$tmp/fastfetch.deb"
  rm -rf "$tmp"
  trap - EXIT
}

install_lazygit_debian() {
  local arch tag
  if apt_has lazygit; then
    apt_install lazygit
    return 0
  fi
  arch="$(linux_arch)" || die "沒有對應的 lazygit 預編版本：$(uname -m)"
  [ "$arch" = "aarch64" ] && arch=arm64
  log "apt 沒有 lazygit，改裝 GitHub 最新版"
  if [ "$DRY_RUN" -eq 1 ]; then
    tag="<最新版>"
  else
    tag="$(github_latest_tag jesseduffield/lazygit)" || die "查不到 lazygit 最新版本"
  fi
  install_release_bin lazygit \
    "https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${tag#v}_linux_${arch}.tar.gz"
}

install_go() {
  local installer="$SCRIPT_DIR/install_go.sh"
  [ -f "$installer" ] || die "找不到 $installer"
  log "用 $installer 安裝最新版 Go"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: bash $installer"
    return 0
  fi
  case "$(uname -s)" in
    Linux) ;;
    *) die "install_go.sh 只適用於 Linux" ;;
  esac
  bash "$installer"
}

install_rust() {
  if [ "$DRY_RUN" -eq 1 ]; then
    if have rustup && [ "$FORCE" -eq 1 ]; then
      log "dry-run: rustup update"
    else
      log "dry-run: curl https://sh.rustup.rs | sh -s -- -y"
    fi
    return 0
  fi
  if have rustup && [ "$FORCE" -eq 1 ]; then
    rustup update
    return 0
  fi
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y
  if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  ensure_cargo_rc
  have rustc || die "rustup 裝完後仍找不到 rustc。請開新的 shell 再試"
}

install_node() {
  log "用 nvm ${NVM_VERSION} 安裝 Node ${NODE_MAJOR}"
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
      log "dry-run: 安裝 nvm ${NVM_VERSION}"
    fi
    log "dry-run: nvm install ${NODE_MAJOR}"
    return 0
  fi
  if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  fi
  ensure_nvm_rc
  # nvm.sh 在 set -u 下會碰到未設定的變數。
  set +u
  # shellcheck disable=SC1091
  . "$HOME/.nvm/nvm.sh"
  nvm install "$NODE_MAJOR"
  set -u
  have node || die "nvm 裝完後仍找不到 node。請開新的 shell 再試"
}

install_trash_pip() {
  log "用 pip 安裝 trash-cli"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: pkg install -y python python-pip"
    log "dry-run: pip install trash-cli"
    return 0
  fi
  pkg install -y python python-pip
  if ! pip install trash-cli; then
    pip install --break-system-packages trash-cli
  fi
  have trash || die "pip 裝完後仍找不到 trash。若它在 ~/.local/bin，請把該目錄加進 PATH"
}

install_fisher() {
  log "安裝 fisher，並裝好 fish_plugins 列的外掛"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: fish -c 'curl … fisher.fish | source; fisher install jorgebucaran/fisher <fish_plugins>'"
    return 0
  fi
  have fish || die "找不到 fish"
  fish -c "$FISHER_INSTALL" || die "fisher 安裝失敗，請看上面的訊息"
}

run_specials() {
  local sidx id
  [ "${#SPECIAL_IDX[@]}" -gt 0 ] || return 0
  for sidx in "${SPECIAL_IDX[@]}"; do
    id="${IDS[$sidx]}"
    case "$OS:$id" in
      fedora:starship | debian:starship) install_starship ;;
      fedora:zellij | debian:zellij) install_zellij_release ;;
      debian:neovim) install_neovim_release ;;
      macos:mitos | fedora:mitos | debian:mitos) install_mitos ;;
      debian:eza) install_eza_debian ;;
      debian:fastfetch) install_fastfetch_debian ;;
      debian:lazygit) install_lazygit_debian ;;
      fedora:go | debian:go) install_go ;;
      macos:rust | fedora:rust | debian:rust) install_rust ;;
      fedora:node | debian:node) install_node ;;
      macos:compiler | macos:make) install_xcode_clt ;;
      termux:trash) install_trash_pip ;;
      *:fisher) install_fisher ;;
      *) die "沒有實作 ${id} 在 $OS 的安裝方式" ;;
    esac
  done
}

install_selected() {
  local i any=0
  FORMULAS=()
  CASKS=()
  DNF_PKGS=()
  APT_PKGS=()
  TERMUX_PKGS=()
  SPECIAL_IDX=()
  SEEN_TOKENS=" "
  QUEUED=0
  SKIPPED=0

  for i in "${!IDS[@]}"; do
    if [ "${SELECTED[$i]}" = "1" ]; then
      any=1
      queue_index "$i"
    fi
  done
  if [ "$any" -eq 0 ]; then
    log "沒有選擇任何套件"
    return 0
  fi
  ensure_deps_for_specials
  if [ "$QUEUED" -eq 0 ]; then
    log "沒有需要安裝的項目"
    return 0
  fi
  run_pkg_plan
  run_specials
  if [ "$DRY_RUN" -eq 1 ]; then
    log "完成（dry-run，沒有真的安裝）。會處理 ${QUEUED} 項，略過已安裝 ${SKIPPED} 項。"
  else
    log "完成。這次處理 ${QUEUED} 項，略過已安裝 ${SKIPPED} 項。"
  fi
  if [ "$TOUCHED_RC" -eq 1 ]; then
    log "shell 設定有更新。請開一個新的終端機，或 source 你的 ~/.zshrc / ~/.bashrc。"
  fi
}

main() {
  local mode="interactive"
  local -a names=()
  local list_only=0

  # 在子 shell 裡 die 只會結束子 shell，所以平台先在這裡定下來。
  if ! OS="$(os_kind)"; then
    exit 1
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --list)
        list_only=1
        shift
        ;;
      --default | --recommended)
        mode="default"
        shift
        ;;
      --all)
        mode="all"
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --simple)
        SIMPLE=1
        shift
        ;;
      --)
        shift
        if [ "$#" -gt 0 ]; then
          names+=("$@")
        fi
        break
        ;;
      -*)
        die "未知參數: $1（見 --help）"
        ;;
      *)
        names+=("$1")
        mode="names"
        shift
        ;;
    esac
  done

  load_catalog
  refresh_states
  log "平台: $OS ($(uname -s 2>/dev/null || echo unknown) $(uname -m 2>/dev/null || echo unknown))"

  if [ "$list_only" -eq 1 ]; then
    list_catalog
    return 0
  fi

  if [ "${#names[@]}" -gt 0 ]; then
    select_names "${names[@]}"
  elif [ "$mode" = "default" ]; then
    select_recommended
  elif [ "$mode" = "all" ]; then
    select_all
  elif can_prompt; then
    interactive_menu
  else
    usage
    exit 1
  fi

  install_selected
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
