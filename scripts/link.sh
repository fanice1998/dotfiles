#!/usr/bin/env bash
# 把這個 dotfiles repo 內各 app 的設定，軟連結到它們該在的位置（多數是 ~/.config/<app>）。
# 可重複執行：已經連好的會略過；碰到實體檔/資料夾會先備份再換成連結。
#
# 用法:
#   ./link.sh                 連結全部項目
#   ./link.sh --list          列出對照表與每個目標的現況
#   ./link.sh --dry-run       只印會做什麼，不動任何檔案
#   ./link.sh ghostty rio     只連指定的 app
#   ./link.sh --dry-run nvim  預覽單一項目
#
# 連結用絕對路徑指向 repo；repo 位置由腳本自己算出來，所以資料夾改名（dotfile→dotfiles）也不會壞。
# 不處理 ~/.zshrc（維持實體檔手動部署），也不碰 scripts/ 本身。

set -euo pipefail

DRY_RUN=0

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

script_dir() {
  cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

SCRIPT_DIR="$(script_dir)"
# repo 根目錄 = scripts/ 的上一層。
REPO_ROOT="$(cd -P -- "$SCRIPT_DIR/.." && pwd)"

# 對照表，欄位用 | 分隔: id|目標(以 $HOME 為基準)|來源(以 $REPO_ROOT 為基準)
# 多數是整個資料夾連到 ~/.config/<app>；starship 是單一檔案。
CATALOG="$(
  cat <<'EOF'
alacritty|.config/alacritty|alacritty
fastfetch|.config/fastfetch|fastfetch
fish|.config/fish|fish
ghostty|.config/ghostty|ghostty
helix|.config/helix|helix
mitos|.config/mitos|mitos
nvim|.config/nvim|nvim
rio|.config/rio|rio
tuios|.config/tuios|tuios
wezterm|.config/wezterm|wezterm
zellij|.config/zellij|zellij
starship|.config/starship.toml|starship/starship.toml
EOF
)"

IDS=()
TARGETS=()
SOURCES=()

load_catalog() {
  local id target source
  while IFS='|' read -r id target source || [ -n "${id:-}" ]; do
    [ -n "${id:-}" ] || continue
    case "$id" in
      \#*)
        id=""
        continue
        ;;
    esac
    IDS+=("$id")
    TARGETS+=("$HOME/$target")
    SOURCES+=("$REPO_ROOT/$source")
    id=""
  done <<EOF
$CATALOG
EOF
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

# 把家目錄縮寫成 ~，印出來短一點。
tilde() {
  case "$1" in
    "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
    "$HOME") printf '~\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# 目標現況: none（不存在）| real（實體檔/資料夾）| link:<指向>
target_state() {
  local t="$1"
  if [ -L "$t" ]; then
    printf 'link:%s\n' "$(readlink "$t")"
  elif [ -e "$t" ]; then
    printf 'real\n'
  else
    printf 'none\n'
  fi
}

list_catalog() {
  local i src_exist state
  printf 'repo: %s\n\n' "$REPO_ROOT"
  printf '%-10s %-26s %s\n' "ID" "目標" "現況"
  printf '%-10s %-26s %s\n' "----------" "--------------------------" "----------"
  for i in "${!IDS[@]}"; do
    if [ "${IDS[$i]}" = "rio" ]; then
      src_exist=""
      [ -e "$REPO_ROOT/rio/config.toml.tmpl" ] || src_exist="  [樣板不存在!]"
      printf '%-10s %-26s %s%s\n' "rio" "$(tilde "${TARGETS[$i]}")" \
        "產生式：config 由樣板產生，fonts/README 連結" "$src_exist"
      continue
    fi
    state="$(target_state "${TARGETS[$i]}")"
    case "$state" in
      none) state="（未連結）" ;;
      real) state="實體檔，會備份" ;;
      link:*)
        if [ "${state#link:}" = "${SOURCES[$i]}" ]; then
          state="已連結 ✓"
        else
          state="連到別處: ${state#link:}"
        fi
        ;;
    esac
    src_exist=""
    [ -e "${SOURCES[$i]}" ] || src_exist="  [來源不存在!]"
    printf '%-10s %-26s %s%s\n' "${IDS[$i]}" "$(tilde "${TARGETS[$i]}")" "$state$src_exist"
  done
}

CREATED=0
RELINKED=0
BACKED=0
SKIPPED=0

# rio 的字體家族名依作業系統而不同（同一顆字型檔內建兩個名稱）。
rio_font_family() {
  case "$(uname -s)" in
    Darwin | Linux) printf '%s\n' "Sarasa Mono TC" ;;         # 英文家族名
    MINGW* | MSYS* | CYGWIN* | Windows_NT) printf '%s\n' "等距更紗黑體 TC" ;; # 繁中家族名
    *) printf '%s\n' "Sarasa Mono TC" ;;
  esac
}

# 確保 dst 是指向 src 的 symlink；既有實體檔會先備份，指錯的 symlink 直接重建。
ensure_symlink() {
  local src="$1" dst="$2" label="$3" bak

  if [ ! -e "$src" ]; then
    warn "跳過 ${label}：來源不存在 $(tilde "$src")"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    log "已連結 ${label}，略過：$(tilde "$dst")"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if [ -L "$dst" ]; then
    log "重新指向 ${label}：$(tilde "$dst") → $(tilde "$src")"
    if [ "$DRY_RUN" -eq 0 ]; then
      rm -f "$dst"
      ln -s "$src" "$dst"
    fi
    RELINKED=$((RELINKED + 1))
    return 0
  fi

  if [ -e "$dst" ]; then
    bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
    log "備份並連結 ${label}：$(tilde "$dst") → 備份到 $(tilde "$bak")"
    if [ "$DRY_RUN" -eq 0 ]; then
      mv "$dst" "$bak"
      ln -s "$src" "$dst"
    fi
    BACKED=$((BACKED + 1))
    return 0
  fi

  log "建立連結 ${label}：$(tilde "$dst") → $(tilde "$src")"
  if [ "$DRY_RUN" -eq 0 ]; then
    ln -s "$src" "$dst"
  fi
  CREATED=$((CREATED + 1))
  return 0
}

# rio 特別處理：config.toml 由樣板依平台產生（真實檔），fonts/README 照舊 symlink。
# （Rio 沒有 import/條件語法，字體家族名只能在連結階段依 OS 填入。）
link_rio() {
  local target="$HOME/.config/rio"
  local srcdir="$REPO_ROOT/rio"
  local tmpl="$srcdir/config.toml.tmpl"
  local family
  family="$(rio_font_family)"

  if [ ! -e "$tmpl" ]; then
    warn "跳過 rio：樣板不存在 $(tilde "$tmpl")"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  # 舊版是「整包目錄 symlink 指向 repo」；要放產生式 config 就得改成真實目錄。
  if [ -L "$target" ]; then
    log "rio: 目標原為整包 symlink，改成真實目錄：$(tilde "$target")"
    if [ "$DRY_RUN" -eq 0 ]; then
      rm -f "$target"
    fi
  fi
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$target"
  fi

  ensure_symlink "$srcdir/fonts" "$target/fonts" "rio/fonts"
  ensure_symlink "$srcdir/README.md" "$target/README.md" "rio/README"

  log "rio: 產生 config.toml（平台 $(uname -s)，字體 \"$family\"）：$(tilde "$target/config.toml")"
  if [ "$DRY_RUN" -eq 0 ]; then
    sed "s|@@SARASA_FAMILY@@|$family|g" "$tmpl" >"$target/config.toml"
  fi
  CREATED=$((CREATED + 1))
  return 0
}

# 建立一個指向 source 的連結，必要時備份既有實體檔。
link_one() {
  local i="$1"

  # rio 走產生式流程（見 link_rio）。
  if [ "${IDS[$i]}" = "rio" ]; then
    link_rio
    return 0
  fi

  local target="${TARGETS[$i]}" source="${SOURCES[$i]}" id="${IDS[$i]}"
  local state bak

  if [ ! -e "$source" ]; then
    warn "跳過 ${id}：來源不存在 $(tilde "$source")"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  state="$(target_state "$target")"
  case "$state" in
    link:"$source")
      log "已連結 ${id}，略過：$(tilde "$target")"
      SKIPPED=$((SKIPPED + 1))
      return 0
      ;;
    link:*)
      # 指到別處或斷掉的連結：移除重建，symlink 沒有資料不必備份。
      log "重新指向 ${id}：$(tilde "$target") → $(tilde "$source")（原本指向 ${state#link:}）"
      if [ "$DRY_RUN" -eq 0 ]; then
        rm -f "$target"
        ln -s "$source" "$target"
      fi
      RELINKED=$((RELINKED + 1))
      return 0
      ;;
    real)
      bak="$target.bak.$(date +%Y%m%d%H%M%S)"
      log "備份並連結 ${id}：$(tilde "$target") → 備份到 $(tilde "$bak")，再連到 $(tilde "$source")"
      if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$(dirname "$target")"
        mv "$target" "$bak"
        ln -s "$source" "$target"
      fi
      BACKED=$((BACKED + 1))
      return 0
      ;;
    none)
      log "建立連結 ${id}：$(tilde "$target") → $(tilde "$source")"
      if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$(dirname "$target")"
        ln -s "$source" "$target"
      fi
      CREATED=$((CREATED + 1))
      return 0
      ;;
  esac
}

usage() {
  cat <<EOF
把 dotfiles repo 內各 app 的設定軟連結到該在的位置（多數是 ~/.config/<app>）。

用法:
  ./link.sh                 連結全部項目
  ./link.sh --list          列出對照表與每個目標的現況
  ./link.sh --dry-run       只印會做什麼，不動任何檔案
  ./link.sh ghostty rio     只連指定的 app（id 見 --list）
  ./link.sh --dry-run nvim  預覽單一項目

處理方式（可重複執行）:
  已指向正確來源   → 略過
  連到別處/斷掉    → 移除重建（symlink 無資料，不備份）
  實體檔/資料夾    → 移到 <目標>.bak.<時間戳> 再建連結
  不存在           → 直接建連結

不處理 ~/.zshrc（維持實體檔手動部署），也不碰 scripts/ 本身。
repo 位置由腳本自己算出，資料夾改名也不會壞。
EOF
}

main() {
  local -a names=()
  local list_only=0 i

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
      --dry-run)
        DRY_RUN=1
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
        shift
        ;;
    esac
  done

  load_catalog

  if [ "$list_only" -eq 1 ]; then
    list_catalog
    return 0
  fi

  log "repo: $REPO_ROOT"

  if [ "${#names[@]}" -gt 0 ]; then
    for name in "${names[@]}"; do
      if ! i="$(index_of "$name")"; then
        die "未知項目: ${name}（見 --list）"
      fi
      link_one "$i"
    done
  else
    for i in "${!IDS[@]}"; do
      link_one "$i"
    done
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "完成（dry-run，沒有真的動檔案）。建立 ${CREATED}、重新指向 ${RELINKED}、備份並連結 ${BACKED}、略過 ${SKIPPED}。"
  else
    log "完成。建立 ${CREATED}、重新指向 ${RELINKED}、備份並連結 ${BACKED}、略過 ${SKIPPED}。"
  fi
  if [ "$BACKED" -gt 0 ]; then
    log "被取代的實體檔已備份成 <目標>.bak.<時間戳>，確認無誤後可自行刪除。"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
