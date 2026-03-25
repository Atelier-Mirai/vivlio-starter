#!/usr/bin/env zsh
#
# install-ruby.zsh — macOS向け Ruby セットアップ（Homebrew + rbenv）
#
# - Homebrew が未導入なら確認のうえインストール
# - rbenv と ruby-build を導入
# - 指定した Ruby をインストール（既定: 最新の安定版）
# - グローバルに切り替え、bundler をインストール
#
# 使い方（Usage）:
#   bin/install-ruby.zsh                 # 対話モード、最新安定版を導入
#   bin/install-ruby.zsh -y              # 非対話モード（自動確認）
#   bin/install-ruby.zsh -v 4.0.2        # 特定の Ruby バージョンを導入
#   bin/install-ruby.zsh -y -v latest    # 全自動（最新安定版）
#
set -euo pipefail

# フォールバック用の既知の安定版（ruby-lang.org で確認済み: 2026-03-16）
FALLBACK_VERSION="4.0.2"

VERSION="latest"
YES="false"
INSTALL_BUNDLER="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      YES="true"; shift ;;
    -v|--version)
      VERSION="${2:-}"; shift 2 ;;
    --no-bundler)
      INSTALL_BUNDLER="false"; shift ;;
    -h|--help)
      cat <<USAGE
使い方: $0 [オプション]
  -y, --yes           非対話モードで実行し、確認を自動承認します
  -v, --version VER   インストールする Ruby のバージョン（既定: latest）。'latest' で自動解決
      --no-bundler    bundler のインストールをスキップ
  -h, --help          このヘルプを表示
USAGE
      exit 0 ;;
    *)
      echo "不明なオプションです: $1" >&2; exit 1 ;;
  esac
done

confirm() {
  local msg="$1"
  if [[ "$YES" == "true" ]]; then
    return 0
  fi
  if [[ -t 0 ]]; then
    printf "%s [y/N]: " "$msg"
    local ans
    read -r ans || true
    [[ "${ans:l}" == "y" ]]
  else
    return 1
  fi
}

echo "⛏️  Xcode コマンドラインツールを確認しています…"
if ! xcode-select -p >/dev/null 2>&1; then
  if confirm "Xcode コマンドラインツールを今すぐインストールしますか？"; then
    xcode-select --install || true
    echo "インストーラのダイアログを完了してください。必要に応じて本スクリプトを再実行してください。"
  else
    echo "CLT のインストールをスキップしました。必要なら次を実行: xcode-select --install"
  fi
fi

is_macos=true
if [[ "$(uname -s)" != "Darwin" ]]; then
  is_macos=false
fi

if $is_macos; then
  echo "🍺 Homebrew を確認しています…"
  if ! command -v brew >/dev/null 2>&1; then
    if confirm "Homebrew が見つかりません。インストールしますか？"; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      # Add brew to PATH for current session (Apple Silicon or Intel)
      if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    else
      echo "このスクリプトは macOS では Homebrew を前提とします。終了します。" >&2
      exit 1
    fi
  else
    # Ensure brew env is loaded for this session
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  echo "📦 rbenv と ruby-build をインストールしています…"
  brew update
  brew install rbenv ruby-build || true
else
  echo "このスクリプトは macOS 向けです。Linux では各ディストリのパッケージマネージャで rbenv と ruby-build を導入後、再実行してください。" >&2
fi

# Ensure rbenv is on PATH for this session
if [[ -x "$(brew --prefix 2>/dev/null)/bin/rbenv" ]]; then
  export PATH="$(brew --prefix)/bin:$PATH"
fi

if ! command -v rbenv >/dev/null 2>&1; then
  echo "PATH に rbenv が見つかりません。シェル初期化に rbenv の設定を追加してから再実行してください。" >&2
  echo "zsh（Apple Silicon）の例:"
  echo "  echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile"
  echo "  echo 'export PATH=\"$HOME/.rbenv/bin:$PATH\"' >> ~/.zprofile"
  echo "  echo 'eval \"$(rbenv init - zsh)\"' >> ~/.zprofile"
  exit 1
fi

# Initialize rbenv for current shell
if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init - zsh)"
fi

# 'latest' が指定された場合は最新安定版を解決
# - プレビュー版（alpha/beta/preview/rc/dev）を除外
# - 正式リリース番号（X.Y.Z）のみを対象とする
if [[ "$VERSION" == "latest" ]]; then
  echo "🔍 rbenv から最新の安定版 Ruby を取得しています…"
  latest="$(rbenv install -l 2>/dev/null \
    | awk '{print $1}' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | grep -vE '(alpha|beta|preview|rc|dev)' \
    | tail -1 \
    | tr -d ' ')"

  if [[ -z "$latest" ]]; then
    # フォールバック: ruby-lang の index から取得（ベストエフォート）
    latest="$(curl -fsSL https://cache.ruby-lang.org/pub/ruby/index.txt 2>/dev/null \
      | grep -E 'ruby-[0-9]+\.[0-9]+\.[0-9]+\.tar\.xz' \
      | grep -vE '(alpha|beta|preview|rc|dev)' \
      | sed -E 's/.*ruby-([0-9]+\.[0-9]+\.[0-9]+).*/\1/' \
      | sort -V \
      | tail -1)"
  fi

  if [[ -n "$latest" ]]; then
    VERSION="$latest"
    echo "➡️  最新安定版を解決しました: ${VERSION}"
  else
    echo "⚠️  最新版を自動取得できませんでした。既知の安定版 ${FALLBACK_VERSION} を使用します"
    VERSION="$FALLBACK_VERSION"
  fi
fi

echo "💎 Ruby ${VERSION} をインストールしています…"
if rbenv versions --bare | grep -qx "${VERSION}"; then
  echo "Ruby ${VERSION} は既にインストール済みです。"
else
  RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@3 2>/dev/null || true)" rbenv install "${VERSION}"
fi

rbenv global "${VERSION}"
rbenv rehash

echo "🔎 バージョン確認: ruby -v"
ruby -v

if [[ "$INSTALL_BUNDLER" == "true" ]]; then
  echo "📦 bundler をインストールしています…"
  gem install bundler
fi

echo "✅ 完了しました。推奨シェル設定（zsh）:"
if [[ -x /opt/homebrew/bin/brew ]]; then
  echo "  echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile"
else
  echo "  echo 'eval \"$(/usr/local/bin/brew shellenv)\"' >> ~/.zprofile"
fi
cat <<'EOT'
  echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.zprofile
  echo 'eval "$(rbenv init - zsh)"' >> ~/.zprofile
  exec zsh -l   # シェルを再読み込み
EOT
