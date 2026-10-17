#!/usr/bin/env zsh
#
# install-ruby.zsh — macOS向け Ruby セットアップ（Homebrew + rbenv）
#
# - Homebrew が未導入なら確認のうえインストール
# - rbenv と ruby-build を導入
# - 指定した Ruby をインストール（既定: 最新の安定版）
# - グローバルに切り替え、bundler をインストール
# - ~/.zprofile に Homebrew と rbenv の設定を書き込む（同じ設定があれば足さない）
#
# 使い方（Usage）:
#   bin/install-ruby.zsh                 # 対話モード、最新安定版を導入
#   bin/install-ruby.zsh -y              # 非対話モード（自動確認）
#   bin/install-ruby.zsh -v 4.0.7        # 特定の Ruby バージョンを導入
#   bin/install-ruby.zsh -y -v latest    # 全自動（最新安定版）
#
# gem を入れる前（Ruby が無い Mac）は GitHub から取って走らせる。`curl … | zsh` に
# しないのは、確認の [y/N] を端末から読めなくなるため（README・11 章・93 章と同じ形）:
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Atelier-Mirai/vivlio-starter/master/bin/install-ruby.zsh)"
#   zsh -c "$(curl -fsSL …/install-ruby.zsh)" install-ruby -y   # オプションは末尾に
#
set -euo pipefail

# 自動解決できなかったときに入れる版。「最新版」ではなく
# **Vivlio Starter が実際に試験している版**を置く（Rakefile の
# SUPPORTED_RUBY_VERSIONS。install_ruby_script_test が一致を見張る）。
# ここが外れると、解決に失敗した人だけ未検証の Ruby を掴むことになる。
FALLBACK_VERSION="4.0.7"

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

# 新しいターミナルで Homebrew と rbenv の Ruby を使うための設定。
# 書かないと、新しいターミナルでは macOS 付属の Ruby 2.6 が使われ、
# gem install が /Library/Ruby/Gems に書けないというエラーで止まる
# （改善案.md #87。何も入っていない Mac で確かめた）。
ZPROFILE="${ZDOTDIR:-$HOME}/.zprofile"

# Homebrew の置き場所は Apple シリコンと Intel で違う
brew_bin() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    print -r -- /opt/homebrew/bin/brew
  else
    print -r -- /usr/local/bin/brew
  fi
}

# ~/.zprofile に足す行。$( ) は書き込む先で展開させるので、ここでは展開しない
shell_setup_lines() {
  print -r -- "eval \"\$($(brew_bin) shellenv)\""
  print -r -- 'eval "$(rbenv init - zsh)"'
}

# すでに同じ設定（コメントでない行）があれば足さない。
# 手で書いた人の書き方（`brew shellenv zsh` など）とも重ならないよう、要の語で見る。
zprofile_has() {
  [[ -f "$ZPROFILE" ]] && grep -qE "^[^#]*$1" "$ZPROFILE"
}

is_macos=true
if [[ "$(uname -s)" != "Darwin" ]]; then
  is_macos=false
fi

if $is_macos && ! xcode-select -p >/dev/null 2>&1; then
  echo "⛏️  Xcode コマンドラインツールを確認しています…"
  if ! command -v brew >/dev/null 2>&1; then
    # Homebrew のインストーラが画面なしで入れるので、ここではダイアログを出さない。
    # 出すと、入った後もインストールを勧めるダイアログが画面に残る（改善案.md #87）
    echo "Xcode コマンドラインツールは、このあと Homebrew と一緒に入ります。"
  elif confirm "Xcode コマンドラインツールを今すぐインストールしますか？"; then
    xcode-select --install || true
    # Ruby を組むのに要るので、入り終わるまで先へ進まない
    echo "インストーラのダイアログを完了してから、もう一度このスクリプトを実行してください。"
    exit 1
  else
    echo "Ruby を組むには Xcode コマンドラインツールが要ります。xcode-select --install で入れてから、もう一度実行してください。" >&2
    exit 1
  fi
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
  # Homebrew 7 から、端末では install のたびに [y/n] を尋ねる。入れることはもう決まっている
  HOMEBREW_NO_ASK=1 brew install rbenv ruby-build || true
else
  echo "このスクリプトは macOS 向けです。Linux では各ディストリのパッケージマネージャで rbenv と ruby-build を導入後、再実行してください。" >&2
fi

# Ensure rbenv is on PATH for this session
if [[ -x "$(brew --prefix 2>/dev/null)/bin/rbenv" ]]; then
  export PATH="$(brew --prefix)/bin:$PATH"
fi

if ! command -v rbenv >/dev/null 2>&1; then
  echo "PATH に rbenv が見つかりません。シェル初期化に rbenv の設定を追加してから再実行してください。" >&2
  echo "~/.zprofile に次の 2 行を足してください:"
  shell_setup_lines | sed 's/^/  /'
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

echo "🐚 シェルの設定を確認しています…"
missing_lines=()
zprofile_has 'brew shellenv' || missing_lines+=("$(shell_setup_lines | sed -n 1p)")
zprofile_has 'rbenv init'    || missing_lines+=("$(shell_setup_lines | sed -n 2p)")

if (( ${#missing_lines} == 0 )); then
  echo "~/.zprofile は設定済みです。"
elif confirm "新しいターミナルでこの Ruby を使うため、~/.zprofile に設定を書き込みますか？"; then
  print -r -l -- "" "# Homebrew と rbenv（Vivlio Starter の install-ruby.zsh が追記）" "${missing_lines[@]}" >> "$ZPROFILE"
  echo "~/.zprofile に書き込みました:"
  print -r -l -- "${missing_lines[@]}" | sed 's/^/  /'
else
  echo "~/.zprofile には書き込みませんでした。使う前に、次の行を足してください:"
  print -r -l -- "${missing_lines[@]}" | sed 's/^/  /'
fi

echo "✅ 完了しました。新しいターミナルを開くと、Ruby ${VERSION} が使えます（このターミナルで続けるなら: exec zsh -l）"
