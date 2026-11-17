#!/bin/zsh

# 僅允許 zsh 執行：shebang 只在直接執行時生效，若被 bash/sh 呼叫則在此攔下
if [ -z "${ZSH_VERSION:-}" ]; then
  echo "錯誤：install_plugin.sh 必須使用 zsh 執行。" >&2
  if command -v zsh >/dev/null 2>&1; then
    echo "請改用：zsh $0" >&2
  else
    echo "系統尚未安裝 zsh，請先安裝，例如：" >&2
    echo "  Debian/Ubuntu: sudo apt install zsh" >&2
    echo "  Fedora:        sudo dnf install zsh" >&2
    echo "  macOS:         brew install zsh" >&2
  fi
  exit 1
fi

# Tips about text history
if [ ! -d ~/.zsh/fzf-tab ]; then
  git clone https://github.com/Aloxaf/fzf-tab ~/.zsh/fzf-tab
fi

# Autosuggestions
if [ ! -d ~/.zsh/zsh-autosuggestions ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
fi

# Syntax highlighting
if [ ! -d ~/.zsh/zsh-syntax-highlighting ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.zsh/zsh-syntax-highlighting
fi

mv ~/.zshrc ~/.zshrc.bak 2>/dev/null

cp ./.zshrc.origin ~/.zshrc

# Go environment
# ── Go environment ──────────────────────────────────────────────
if command -v go >/dev/null 2>&1; then
  if ! grep -qF 'GOROOT="$(go env GOROOT)"' ~/.zshrc 2>&1; then
    echo 'export GOROOT="$(go env GOROOT)"' >> ~/.zshrc
    echo 'export GOPATH="$(go env GOPATH)"' >> ~/.zshrc
    echo 'export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"' >> ~/.zshrc
  fi
fi

# starship install and setting zshrc
if command -v starship >/dev/null 2>&1; then
  if ! grep -qF 'eval "$(starship init zsh)"' ~/.zshrc 2>/dev/null; then
    echo 'eval "$(starship init zsh)"' >> ~/.zshrc
  fi
else
  curl -sS https://starship.rs/install.sh | sh
  echo 'eval "$(starship init zsh)"' >> ~/.zshrc
fi

# reload
source ~/.zshrc

