#!/bin/bash
# =============================================
# Go 最新版自動安裝腳本
# 使用方式：bash install_go.sh
# /usr/local 不可寫時，只對安裝步驟使用 sudo。
# shell 設定寫入原本使用者的家目錄，避免 sudo 把
# PATH 寫進 /root，或把 /usr/local/go 留成 root 擁有。
# =============================================

set -euo pipefail

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    owner="$SUDO_USER"
    # Linux 看 /etc/passwd。macOS 的本地使用者多半只在 Directory Services。
    owner_home="$(awk -F: -v u="$SUDO_USER" '$1==u {print $6; exit}' /etc/passwd)"
    if [ -z "$owner_home" ] && command -v dscacheutil >/dev/null 2>&1; then
        owner_home="$(dscacheutil -q user -a name "$SUDO_USER" | awk '/^dir: / {print $2; exit}')"
    fi
    if [ -z "$owner_home" ] && command -v getent >/dev/null 2>&1; then
        owner_home="$(getent passwd "$SUDO_USER" | awk -F: '{print $6; exit}')"
    fi
else
    owner="$(id -un)"
    owner_home="$HOME"
fi

if [ -z "$owner_home" ] || [ ! -d "$owner_home" ]; then
    echo "❌ 找不到 ${owner} 的家目錄，無法寫入 shell 設定"
    exit 1
fi

need_root=0
if [ ! -w /usr/local ] || { [ -e /usr/local/go ] && [ ! -w /usr/local/go ]; }; then
    need_root=1
fi

elevate() {
    if [ "$(id -u)" -eq 0 ] || [ "$need_root" -eq 0 ]; then
        "$@"
    else
        if ! command -v sudo >/dev/null 2>&1; then
            echo "❌ 沒有寫入 /usr/local 的權限，而且找不到 sudo"
            exit 1
        fi
        sudo "$@"
    fi
}

# GNU stat 用 -c；macOS 的 BSD stat 用 -f。
file_owner() {
    if [ "$(uname -s)" = "Darwin" ]; then
        stat -f '%Su' "$1"
    else
        stat -c '%U' "$1"
    fi
}

case "$(uname -s)" in
    Linux) goos=linux ;;
    Darwin) goos=darwin ;;
    *)
        echo "❌ 不支援的系統：$(uname -s)"
        exit 1
        ;;
esac

case "$(uname -m)" in
    x86_64|amd64) goarch=amd64 ;;
    aarch64|arm64) goarch=arm64 ;;
    armv6l|armv7l) goarch=armv6l ;;
    i386|i686) goarch=386 ;;
    *)
        echo "❌ 不支援的架構：$(uname -m)"
        exit 1
        ;;
esac

echo "開始安裝最新版 Go ..."

# 取得最新版本（官方端點）
echo "📡 正在取得最新版本號..."
version_text="$(curl -fsSL https://go.dev/VERSION?m=text)"
version="${version_text%%$'\n'*}"
version="${version%%$'\r'*}"
echo "✅ 最新版本：${version}（${goos}-${goarch}）"

filename="${version}.${goos}-${goarch}.tar.gz"
download_url="https://go.dev/dl/${filename}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# 先下載到暫存目錄。失敗時保留原本的 /usr/local/go，
# 也不在目前目錄留下 root 擁有的壓縮檔。
echo "⬇️  下載中：${download_url}"
curl -fL "$download_url" -o "${workdir}/${filename}"

# 移除舊版 Go（目錄在但不在 PATH 上時也要清掉）
if [ -d /usr/local/go ]; then
    echo "⚠️  偵測到已安裝：/usr/local/go"
    echo "🗑️  正在移除舊版 /usr/local/go ..."
    elevate rm -rf /usr/local/go
fi

echo "📦 解壓縮到 /usr/local/go ..."
elevate tar -C /usr/local -xzf "${workdir}/${filename}"

go_owner="$(file_owner /usr/local/go)"
if [ "$go_owner" != "$owner" ]; then
    echo "🔧 將 /usr/local/go 擁有者改為 ${owner} ..."
    elevate chown -R "${owner}:$(id -gn "$owner")" /usr/local/go
fi

# 設定永久 PATH。sudo 時寫入原使用者的 rc，不寫 /root。
echo "🔧 設定環境變數..."
path_line='export PATH="$PATH:/usr/local/go/bin"'

append_rc() {
    local rc="$1"
    if [ -f "$rc" ] && grep -qF '/usr/local/go/bin' "$rc"; then
        echo "ℹ️  PATH 已設定：${rc}"
        return 0
    fi
    local created=0
    if [ ! -e "$rc" ]; then
        created=1
    fi
    printf '\n%s\n' "$path_line" >> "$rc"
    if [ "$created" -eq 1 ] && [ "$(id -u)" -eq 0 ] && [ "$owner" != "root" ]; then
        chown "${owner}:$(id -gn "$owner")" "$rc"
    fi
    echo "✅ 已寫入 ${rc}"
}

append_rc "${owner_home}/.bashrc"
if [ -f "${owner_home}/.zshrc" ]; then
    append_rc "${owner_home}/.zshrc"
fi

export PATH="/usr/local/go/bin:${PATH}"

echo ""
echo "🎉 安裝完成！"
if ! go version; then
    echo "❌ /usr/local/go/bin/go 無法在這個系統執行"
    exit 1
fi

echo ""
reload_rc="${owner_home}/.bashrc"
current_shell="${SHELL:-}"
if [ "${current_shell##*/}" = "zsh" ] && [ -f "${owner_home}/.zshrc" ]; then
    reload_rc="${owner_home}/.zshrc"
fi
echo "✅ 請重新開啟終端機，或執行：source ${reload_rc}"
echo "   之後就可以直接使用 go 指令了！"
