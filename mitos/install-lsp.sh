#!/usr/bin/env bash
# 安裝 mitos（Helix）languages.toml 用到的 language server，執行時自己勾選要裝哪些。
# 支援 macOS、Fedora、Debian / Ubuntu。
#
# 用法:
#   ./install-lsp.sh                 方向鍵移動、空白鍵勾選、Enter 安裝
#   ./install-lsp.sh --simple        改用輸入編號勾選（終端機不支援方向鍵時）
#   ./install-lsp.sh --list          列出項目與這個平台的安裝方式
#   ./install-lsp.sh --default       只裝預設項目
#   ./install-lsp.sh --all           安裝清單裡的全部項目
#   ./install-lsp.sh gopls taplo     只裝指定 id
#   ./install-lsp.sh --dry-run --all 只印出會執行的指令
#   ./install-lsp.sh --force gopls   已安裝的也重裝
#
# Bash 3.2（macOS /bin/bash）可用。
#
# 各 LSP 需要的語言工具鏈（node/npm、go、rustup 或 cargo、JDK、Dart SDK）不會由這個腳本安裝。
# 選到的項目若缺工具鏈，會印出警告並略過，其餘照裝。工具鏈請先用 ../scripts/install-packages.sh 安裝。

set -euo pipefail

DRY_RUN=0
FORCE=0
SIMPLE=0
TOUCHED_RC=0
CURRENT_ID=""

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

# macos | fedora | debian
os_kind() {
  if [ -n "${OS_KIND:-}" ]; then
    case "$OS_KIND" in
      macos | fedora | debian)
        printf '%s\n' "$OS_KIND"
        return 0
        ;;
      ubuntu)
        printf 'debian\n'
        return 0
        ;;
      *)
        die "OS_KIND 只能是 macos、fedora、debian（ubuntu）"
        ;;
    esac
  fi
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) OS_KIND=macos ;;
    Linux)
      if is_fedora; then
        OS_KIND=fedora
      elif is_debian; then
        OS_KIND=debian
      else
        die "只支援 macOS、Fedora、Debian / Ubuntu"
      fi
      ;;
    *)
      die "只支援 macOS、Fedora、Debian / Ubuntu（目前是 $(uname -s 2>/dev/null || echo unknown)）"
      ;;
  esac
  printf '%s\n' "$OS_KIND"
}

# 欄位用 | 分隔: id|群組|預設(1/0)|檢查的指令|說明
# 群組只影響清單裡的分段顯示。安裝方式依 id 分派（見 install_dispatch）。
CATALOG="$(
  cat <<'EOF'
gopls|go|1|gopls|Go
typescript-language-server|web|1|typescript-language-server|TypeScript / React（tsx、jsx）
vscode-json|web|1|vscode-json-language-server|JSON（vscode-langservers-extracted）
yaml-language-server|web|1|yaml-language-server|YAML
csv-lsp|web|0|csv-language-server|CSV / TSV（無公開套件，需自行安裝）
rust-analyzer|rust|1|rust-analyzer|Rust
taplo|rust|1|taplo|TOML
marksman|other|1|marksman|Markdown
intelephense|other|1|intelephense|PHP
kotlin-language-server|other|0|kotlin-language-server|Kotlin（需 JDK 21）
dart|other|0|dart|Dart（需 Dart SDK）
EOF
)"

IDS=()
CATS=()
RECS=()
CHECKS=()
DESCS=()
SELECTED=()
# 每項的狀態: installed | missing。畫選單時用。
STATE=()

load_catalog() {
  local id group rec check desc
  # read 在最後一行沒有換行時會回傳失敗，但仍有讀到內容。清掉 id，避免 EOF 時重複最後一筆。
  while IFS='|' read -r id group rec check desc || [ -n "${id:-}" ]; do
    [ -n "${id:-}" ] || continue
    case "$id" in
      \#*)
        id=""
        continue
        ;;
    esac
    IDS+=("$id")
    CATS+=("$group")
    RECS+=("$rec")
    CHECKS+=("$check")
    DESCS+=("$desc")
    SELECTED+=(0)
    id=""
  done <<EOF
$CATALOG
EOF
}

group_name() {
  case "$1" in
    go) printf 'Go\n' ;;
    web) printf 'Web / 設定檔\n' ;;
    rust) printf 'Rust 系\n' ;;
    other) printf '其他\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# 這個腳本的項目在三個平台都能裝（只是方式不同），一律視為可用。
is_available() {
  return 0
}

is_installed() {
  have "${CHECKS[$1]}"
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

# --list 與選單裡顯示的「這個平台怎麼裝」。
method_label() {
  local id="${IDS[$1]}"
  case "$id" in
    gopls) printf '%s\n' "go install golang.org/x/tools/gopls@latest" ;;
    typescript-language-server) printf '%s\n' "npm -g typescript-language-server typescript" ;;
    vscode-json) printf '%s\n' "npm -g vscode-langservers-extracted" ;;
    yaml-language-server) printf '%s\n' "npm -g yaml-language-server" ;;
    intelephense) printf '%s\n' "npm -g intelephense" ;;
    csv-lsp) printf '%s\n' "無公開套件，需自行安裝" ;;
    rust-analyzer)
      if [ "$OS" = "macos" ]; then
        printf '%s\n' "rustup component add rust-analyzer（或 brew）"
      else
        printf '%s\n' "rustup component add rust-analyzer"
      fi
      ;;
    taplo)
      if [ "$OS" = "macos" ]; then
        printf '%s\n' "brew install taplo"
      else
        printf '%s\n' "cargo install taplo-cli --features lsp"
      fi
      ;;
    marksman)
      if [ "$OS" = "macos" ]; then
        printf '%s\n' "brew install marksman"
      else
        printf '%s\n' "GitHub 最新版 → ~/.local/bin"
      fi
      ;;
    kotlin-language-server)
      if [ "$OS" = "macos" ]; then
        printf '%s\n' "brew install kotlin-language-server"
      else
        printf '%s\n' "fwcd GitHub 最新版 → ~/.local（需 JDK 21）"
      fi
      ;;
    dart)
      if [ "$OS" = "macos" ]; then
        printf '%s\n' "brew install dart-sdk"
      else
        printf '%s\n' "手動安裝 Dart SDK"
      fi
      ;;
    *) printf '%s\n' "專用安裝" ;;
  esac
}

usage() {
  cat <<EOF
安裝 mitos（Helix）languages.toml 用到的 language server。每次只裝你選的項目。
支援 macOS、Fedora、Debian / Ubuntu。

用法:
  ./install-lsp.sh                 自己選要裝哪些（方向鍵 + 空白鍵）
  ./install-lsp.sh --simple        改用輸入編號勾選
  ./install-lsp.sh --list          列出 id、狀態、這個平台的裝法
  ./install-lsp.sh --default       只裝預設項目裡還沒裝的
  ./install-lsp.sh --all           安裝清單裡還沒裝的全部項目
  ./install-lsp.sh gopls taplo     只裝這些 id
  ./install-lsp.sh --dry-run --all 只印出會執行的指令
  ./install-lsp.sh --force gopls   已安裝的也重做

不帶參數時開啟勾選清單，一開始已勾好「預設項目裡還沒裝的」，直接按 Enter 就能裝。
  ↑ ↓ / j k   移動
  空白 / x    勾選或取消
  a           改勾預設項目裡還沒裝的
  A           勾全部項目
  n           清空
  Enter       開始安裝
  q / Esc     取消
  已安裝又被勾到時會略過。要重裝請加上 --force。

--simple（或終端機不支援時）改用輸入編號:
  2 5 7       同時切換這三個（也可以用逗號分開）
  3-6         勾起 3 到 6
  gopls taplo 也可以打 id
  a / A / n   同上
  d           開始安裝
  q           取消

預設（--default，或清單裡按 a）不含: csv-lsp、kotlin-language-server、dart。

工具鏈（不由這個腳本安裝，缺少時會略過並提示）:
  npm / node   typescript、vscode-json、yaml、intelephense
  go           gopls
  rustup       rust-analyzer（mac 可改用 brew）
  cargo        taplo（mac 改用 brew install taplo）
  JDK 21       kotlin-language-server（Linux）
  Dart SDK     dart（Linux 需手動安裝）
  以上語言工具鏈請用 ../scripts/install-packages.sh 先裝好。

各平台的裝法:
  macOS    Homebrew（marksman、taplo、kotlin、dart、rust-analyzer 退路）。npm / go / cargo 直接用。
  Fedora   rust-analyzer 用 rustup component、taplo 用 cargo、marksman / kotlin 抓 GitHub 版到 ~/.local。
  Debian   同 Fedora（含 Ubuntu 與衍生版）。

csv-lsp 的 csv-language-server 在 npm / PyPI / crates 都查不到公開套件，選到會略過並提示自行安裝。

環境變數:
  OS_KIND      覆寫平台偵測（macos、fedora、debian），用來預覽別的平台
EOF
}

list_catalog() {
  local i rec state
  printf '平台: %s (%s)\n\n' "$OS" "$(uname -m 2>/dev/null || echo unknown)"
  printf '%-28s %-6s %-8s %s\n' "ID" "預設" "狀態" "這個平台"
  printf '%-28s %-6s %-8s %s\n' "----------------------------" "------" "--------" "----------"
  for i in "${!IDS[@]}"; do
    if [ "${RECS[$i]}" = "1" ]; then
      rec="是"
    else
      rec="-"
    fi
    state="$(state_label "$i")"
    printf '%-28s %-6s %-8s %s\n' "${IDS[$i]}" "$rec" "$state" "$(method_label "$i")"
    printf '%-28s %-6s %-8s %s\n' "" "" "" "${DESCS[$i]}"
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

  out="${esc}[H${esc}[1m選擇要安裝的 LSP${esc}[0m  平台 $OS  ${esc}[2m* 是預設項目${esc}[0m${esc}[K"$'\n'
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
        out="$out$hl$(printf ' %s [%s] %s %-26s ' "$pointer" "$mark" "$rec" "${IDS[$i]}")"
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
    printf '  %2d [%s] %s %-26s %s  %s\n' \
      "$((i + 1))" "$mark" "$recmark" "${IDS[$i]}" "$(state_label "$i")" "${DESCS[$i]}"
  done
  printf '\n'
  print_checked
  printf '輸入編號切換勾選，例如 2 5 7；3-6 勾起一段；也可以打 id\n'
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

# 3-6 這種範圍一律勾起（不是切換），這個平台沒有的項目直接跳過。
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
      die "未知 LSP: $name（見 --list）"
    fi
    if ! is_available "$i"; then
      die "${name} 在 $OS 沒有對應安裝方式"
    fi
    SELECTED[$i]=1
  done
}

# ---- 共用安裝工具 ----

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    if ! have sudo; then
      die "需要 sudo 才能安裝"
    fi
    sudo "$@"
  fi
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
    printf '\n# dotfile install-lsp\n%s\n' "$text" >>"$file"
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

# 選到但缺工具鏈 / 沒有安裝來源時：印警告、計入略過、回傳 1。
skip_tool() {
  warn "$1"
  SKIP_TOOL=$((SKIP_TOOL + 1))
  return 1
}

# x64 或 arm64；其他架構沒有預編版本。
release_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'x64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    *) return 1 ;;
  esac
}

brew_install() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: brew install $*"
    return 0
  fi
  if ! have brew; then
    skip_tool "跳過 $CURRENT_ID：找不到 Homebrew，請先安裝 https://brew.sh"
    return 1
  fi
  log "brew install $*"
  brew install "$@" || die "brew install 失敗：$*"
}

# npm install -g。npm prefix 不可寫（系統 node）又非 root 時加 sudo。
npm_global() {
  local prefix sudo=0
  prefix="$(npm config get prefix 2>/dev/null || true)"
  if [ "$(id -u)" -ne 0 ] && [ -n "$prefix" ] && [ ! -w "$prefix" ]; then
    sudo=1
  fi
  if [ "$sudo" -eq 1 ]; then
    log "sudo npm install -g $*"
  else
    log "npm install -g $*"
  fi
  [ "$DRY_RUN" -eq 1 ] && return 0
  if [ "$sudo" -eq 1 ]; then
    as_root env PATH="$PATH" npm install -g "$@" || die "npm install 失敗：$*"
  else
    npm install -g "$@" || die "npm install 失敗：$*"
  fi
}

# 下載單一執行檔到 ~/.local/bin。
install_raw_bin() {
  local name="$1" url="$2" tmp
  ensure_local_bin
  log "下載 $name → ~/.local/bin/$name"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: curl -fL $url → ~/.local/bin/$name"
    return 0
  fi
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT
  curl -fL --retry 3 --retry-delay 1 -o "$tmp" "$url" || die "下載失敗：$url"
  install -m 755 "$tmp" "$HOME/.local/bin/$name" || die "安裝 $name 失敗"
  rm -f "$tmp"
  trap - EXIT
  log "已安裝 ~/.local/bin/$name"
}

# ---- 每個 LSP 的安裝 ----

do_npm() {
  local id="$1"
  shift
  if ! have npm; then
    skip_tool "跳過 $id：需要 npm（node），請先執行 ../scripts/install-packages.sh node"
    return 1
  fi
  npm_global "$@"
}

do_gopls() {
  local gobin
  if ! have go; then
    skip_tool "跳過 gopls：需要 go，請先執行 ../scripts/install-packages.sh go"
    return 1
  fi
  log "go install golang.org/x/tools/gopls@latest"
  if [ "$DRY_RUN" -eq 0 ]; then
    go install golang.org/x/tools/gopls@latest || die "go install gopls 失敗"
  fi
  gobin="$(go env GOBIN 2>/dev/null || true)"
  [ -n "$gobin" ] || gobin="$(go env GOPATH 2>/dev/null || echo "$HOME/go")/bin"
  case ":$PATH:" in
    *":$gobin:"*) ;;
    *) warn "記得把 $gobin 加進 PATH，Helix 才找得到 gopls" ;;
  esac
}

do_rust_analyzer() {
  if have rustup; then
    log "rustup component add rust-analyzer"
    if [ "$DRY_RUN" -eq 0 ]; then
      rustup component add rust-analyzer || die "rustup component add rust-analyzer 失敗"
      have rust-analyzer || warn "rust-analyzer 已加入 rustup，但 PATH 找不到，確認 ~/.cargo/bin 在 PATH"
    fi
    return 0
  fi
  if [ "$OS" = "macos" ]; then
    brew_install rust-analyzer
    return
  fi
  skip_tool "跳過 rust-analyzer：需要 rustup，請先執行 ../scripts/install-packages.sh rust"
  return 1
}

do_taplo() {
  if [ "$OS" = "macos" ]; then
    brew_install taplo
    return
  fi
  if ! have cargo; then
    skip_tool "跳過 taplo：需要 cargo（rust），請先執行 ../scripts/install-packages.sh rust"
    return 1
  fi
  log "cargo install taplo-cli --locked --features lsp"
  if [ "$DRY_RUN" -eq 0 ]; then
    cargo install taplo-cli --locked --features lsp || die "cargo install taplo 失敗"
  fi
}

do_marksman() {
  local arch
  if [ "$OS" = "macos" ]; then
    brew_install marksman
    return
  fi
  if ! have curl; then
    skip_tool "跳過 marksman：需要 curl"
    return 1
  fi
  if ! arch="$(release_arch)"; then
    skip_tool "跳過 marksman：沒有對應的預編版本（$(uname -m)）"
    return 1
  fi
  install_raw_bin marksman \
    "https://github.com/artempyanykh/marksman/releases/latest/download/marksman-linux-${arch}"
}

do_kotlin() {
  local url dest tmp
  if [ "$OS" = "macos" ]; then
    brew_install kotlin-language-server
    return
  fi
  if ! have java; then
    skip_tool "跳過 kotlin-language-server：需要 JDK 21，請先安裝 JDK"
    return 1
  fi
  if ! have curl; then
    skip_tool "跳過 kotlin-language-server：需要 curl"
    return 1
  fi
  if ! have unzip; then
    skip_tool "跳過 kotlin-language-server：需要 unzip"
    return 1
  fi
  url="https://github.com/fwcd/kotlin-language-server/releases/latest/download/server.zip"
  dest="$HOME/.local/opt/kotlin-language-server"
  ensure_local_bin
  log "安裝 kotlin-language-server → $dest"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: curl -fL $url → $dest，連結 ~/.local/bin/kotlin-language-server"
    return 0
  fi
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  curl -fL --retry 3 --retry-delay 1 -o "$tmp/server.zip" "$url" || die "下載失敗：$url"
  unzip -q "$tmp/server.zip" -d "$tmp" || die "解壓 server.zip 失敗"
  [ -x "$tmp/server/bin/kotlin-language-server" ] || die "壓縮檔裡找不到 kotlin-language-server"
  mkdir -p "$HOME/.local/opt"
  rm -rf "$dest"
  mv "$tmp/server" "$dest"
  ln -sf "$dest/bin/kotlin-language-server" "$HOME/.local/bin/kotlin-language-server"
  rm -rf "$tmp"
  trap - EXIT
  log "已安裝 ~/.local/bin/kotlin-language-server"
}

do_dart() {
  if [ "$OS" = "macos" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "dry-run: brew tap dart-lang/dart && brew install dart-sdk"
      return 0
    fi
    if ! have brew; then
      skip_tool "跳過 dart：找不到 Homebrew，請先安裝 https://brew.sh"
      return 1
    fi
    log "brew tap dart-lang/dart && brew install dart-sdk"
    brew tap dart-lang/dart || die "brew tap dart-lang/dart 失敗"
    brew install dart-sdk || die "brew install dart-sdk 失敗"
    return 0
  fi
  skip_tool "跳過 dart：Linux 請手動安裝 Dart SDK（https://dart.dev/get-dart）"
  return 1
}

do_csv() {
  skip_tool "跳過 csv-lsp：csv-language-server 在 npm / PyPI / crates 都查不到公開套件，請自行安裝後再使用"
  return 1
}

install_dispatch() {
  case "$1" in
    gopls) do_gopls ;;
    typescript-language-server) do_npm typescript-language-server typescript-language-server typescript ;;
    vscode-json) do_npm vscode-json vscode-langservers-extracted ;;
    yaml-language-server) do_npm yaml-language-server yaml-language-server ;;
    intelephense) do_npm intelephense intelephense ;;
    csv-lsp) do_csv ;;
    rust-analyzer) do_rust_analyzer ;;
    taplo) do_taplo ;;
    marksman) do_marksman ;;
    kotlin-language-server) do_kotlin ;;
    dart) do_dart ;;
    *) die "沒有實作 $1 的安裝" ;;
  esac
}

DID=0
SKIP_INSTALLED=0
SKIP_TOOL=0

install_one() {
  local i="$1" id="${IDS[$i]}"
  CURRENT_ID="$id"
  if [ "$FORCE" -eq 0 ] && is_installed "$i"; then
    log "已安裝 $id，略過（要重裝加 --force）"
    SKIP_INSTALLED=$((SKIP_INSTALLED + 1))
    return 0
  fi
  if install_dispatch "$id"; then
    DID=$((DID + 1))
  fi
}

install_selected() {
  local i any=0
  DID=0
  SKIP_INSTALLED=0
  SKIP_TOOL=0
  for i in "${!IDS[@]}"; do
    if [ "${SELECTED[$i]}" = "1" ]; then
      any=1
      install_one "$i"
    fi
  done
  if [ "$any" -eq 0 ]; then
    log "沒有選擇任何 LSP"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "完成（dry-run，沒有真的安裝）。會處理 $DID 項，已安裝略過 $SKIP_INSTALLED 項，缺工具鏈/來源略過 $SKIP_TOOL 項。"
  else
    log "完成。處理 $DID 項，已安裝略過 $SKIP_INSTALLED 項，缺工具鏈/來源略過 $SKIP_TOOL 項。"
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
