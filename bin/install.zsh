#!/usr/bin/env zsh
#
# install.zsh — macOS 向け Vivlio Starter の導入（Homebrew → Ruby → Vivlio Starter → ツール一式）
#
# - Homebrew が未導入なら確認のうえインストール（Xcode コマンドラインツールも一緒に入る）
# - rbenv と ruby-build を導入し、指定した Ruby をインストール（既定: 最新の安定版）
# - グローバルに切り替え、bundler をインストール
# - ~/.zprofile に Homebrew と rbenv の設定を書き込む（同じ設定があれば足さない）
# - 尋ねること（Homebrew・~/.zprofile・プレビューの操作の許可）は最初にまとめる
# - Vivlio Starter（gem）を入れ、執筆に使うツール一式を vivlio-starter doctor --fix で入れる
#
# 使い方（Usage）:
#   bin/install.zsh                      # 対話モード、最新安定版を導入
#   bin/install.zsh -y                   # 非対話モード（自動確認）
#   bin/install.zsh -v 4.0.7             # 特定の Ruby バージョンを導入
#   bin/install.zsh --gem ./vivlio-starter.gem   # 手元の gem を入れる（公開前の確かめ用）
#
# gem を入れる前（Ruby が無い Mac）は GitHub から取って走らせる。`curl … | zsh` に
# しないのは、確認の [y/N] を端末から読めなくなるため（README・11 章・93 章と同じ形）:
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Atelier-Mirai/vivlio-starter/master/bin/install.zsh)"
#   zsh -c "$(curl -fsSL …/install.zsh)" install -y   # オプションは末尾に
#
# 以前の名前は install-ruby.zsh。Ruby だけでなく Vivlio Starter とツールまで入れるようにした
# ので改めた（改善案.md #87。gem を入れたあと vs new でまたツールの導入が始まり、待たされた）。
#
set -euo pipefail

# 自動解決できなかったときに入れる版。「最新版」ではなく
# **Vivlio Starter が実際に試験している版**を置く（Rakefile の
# SUPPORTED_RUBY_VERSIONS。install_script_test が一致を見張る）。
# ここが外れると、解決に失敗した人だけ未検証の Ruby を掴むことになる。
FALLBACK_VERSION="4.0.7"

VERSION="latest"
YES="false"
INSTALL_BUNDLER="true"
GEM_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      YES="true"; shift ;;
    -v|--version)
      VERSION="${2:-}"; shift 2 ;;
    --gem)
      GEM_FILE="${2:-}"; shift 2 ;;
    --no-bundler)
      INSTALL_BUNDLER="false"; shift ;;
    -h|--help)
      cat <<USAGE
使い方: $0 [オプション]
  -y, --yes           非対話モードで実行し、確認を自動承認します
  -v, --version VER   インストールする Ruby のバージョン（既定: latest）。'latest' で自動解決
      --gem FILE      rubygems からでなく、手元の gem ファイルから Vivlio Starter を入れます
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

# 押すもの・打つものだけを緑にする（端末に出すときだけ。vs の枠の案内と同じ決まり）
green() {
  if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    print -rn -- $'\e[32m'"$1"$'\e[0m'
  else
    print -rn -- "$1"
  fi
}

# 新しいターミナルで Homebrew と rbenv の Ruby を使うための設定。
# 書かないと、新しいターミナルでは macOS 付属の Ruby 2.6 が使われ、
# gem install が /Library/Ruby/Gems に書けないというエラーで止まる
# （改善案.md #87。何も入っていない Mac で確かめた）。
ZPROFILE="${ZDOTDIR:-$HOME}/.zprofile"

# Homebrew の置き場所は Apple シリコンと Intel で違う。まだ入っていないときは CPU の種類で決める
# （~/.zprofile に書くかどうかを、Homebrew を入れる前に尋ねるため）
brew_bin() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    print -r -- /opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew || "$(uname -m)" != "arm64" ]]; then
    print -r -- /usr/local/bin/brew
  else
    print -r -- /opt/homebrew/bin/brew
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

echo "📚 Vivlio Starter を導入します（Homebrew・Ruby・Vivlio Starter・執筆に使うツール）。"
echo "   15 分ほどかかります。最初にいくつか確かめます。"
echo ""

# --- Phase: Xcode コマンドラインツール ---
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

# --- Phase: はじめの確認 ---
# 尋ねることは最初にまとめる。導入は 15 分ほどかかり、途中や最後に尋ねると、席を外した著者が
# 確認を見逃したり、戻ってきてから続きの導入が始まったりする（改善案.md #87・ユーザーの指摘）。
install_homebrew=false
if $is_macos && ! command -v brew >/dev/null 2>&1; then
  if confirm "Homebrew が見つかりません。インストールしますか？"; then
    install_homebrew=true
  else
    echo "このスクリプトは macOS では Homebrew を前提とします。終了します。" >&2
    exit 1
  fi
fi

missing_lines=()
zprofile_has 'brew shellenv' || missing_lines+=("$(shell_setup_lines | sed -n 1p)")
zprofile_has 'rbenv init'    || missing_lines+=("$(shell_setup_lines | sed -n 2p)")
write_zprofile=false
if (( ${#missing_lines} > 0 )) && confirm "新しいターミナルで Ruby を使えるよう、~/.zprofile に設定を書き込みますか？"; then
  write_zprofile=true
fi

# ビルドのあと、前の PDF を閉じて新しい PDF を決まった位置に開くのに、プレビューを操作する。
# 初めてのときは macOS が許可を尋ねるので、著者が画面の前にいる今ここで尋ねておく。
# 初めてのビルドの最後に尋ねると、席を外していれば 60 秒待ってしまう。
# 端末が無いとき（CI など）は確認に答えられないので尋ねない。
if $is_macos && [[ -t 0 ]]; then
  echo "🖨  PDF を開くときに使う「プレビュー」の操作を確かめます。"
  print -rn -- "   macOS の確認が出たら"; green "「許可」"; print -r -- "を押してください。"
  preview_was_running=false
  pgrep -xq Preview && preview_was_running=true
  if osascript -e 'tell application "Preview" to count windows' >/dev/null 2>&1; then
    echo "✅ プレビューの操作が許可されました"
  else
    echo "許可しなくても PDF は開きます。あとから許可するには:"
    echo "  システム設定 → プライバシーとセキュリティ → オートメーション"
    echo "  → お使いのターミナル（またはエディタ）→「プレビュー」をオン"
  fi
  # 確かめるために起動したプレビューは閉じる（もとから開いていたなら、そのままにする）
  $preview_was_running || osascript -e 'tell application "Preview" to quit' >/dev/null 2>&1 || true
fi

echo ""
if $install_homebrew; then
  echo "続けて、Homebrew のインストーラがパスワード（Mac にログインするときのもの）と RETURN（Enter）を尋ねます。"
  echo "それが済めば、終わるまで席を外して構いません。"
else
  echo "確認は以上です。終わるまで席を外して構いません。"
fi
echo ""

# --- Phase: Homebrew・rbenv ---
if $is_macos; then
  echo "🍺 Homebrew を確認しています…"
  if $install_homebrew; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  # このシェルで brew を使えるようにする（Apple シリコン・Intel のどちらでも）
  eval "$("$(brew_bin)" shellenv)"

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

eval "$(rbenv init - zsh)"

# --- Phase: Ruby ---
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

# --- Phase: シェルの設定 ---
# 書くかどうかは最初に尋ねてある。この後の gem やツールの導入が途中で失敗しても、
# 新しいターミナルで Ruby を使えるよう、先に書く
echo "🐚 シェルの設定を確認しています…"
if (( ${#missing_lines} == 0 )); then
  echo "~/.zprofile は設定済みです。"
elif $write_zprofile; then
  print -r -l -- "" "# Homebrew と rbenv（Vivlio Starter の install.zsh が追記）" "${missing_lines[@]}" >> "$ZPROFILE"
  echo "~/.zprofile に書き込みました:"
  print -r -l -- "${missing_lines[@]}" | sed 's/^/  /'
else
  echo "~/.zprofile には書き込みませんでした。使う前に、次の行を足してください:"
  print -r -l -- "${missing_lines[@]}" | sed 's/^/  /'
fi

# --- Phase: Vivlio Starter ---
echo "📚 Vivlio Starter をインストールしています…"
if [[ -n "$GEM_FILE" ]]; then
  gem install "$GEM_FILE"
else
  gem install vivlio-starter
fi
rbenv rehash

echo "🔎 バージョン確認: vs --version"
# `vs` でなく正式名で呼ぶ。Vivliostyle CLI も `vs` という別名を入れるため（改善案.md #87）
vivlio-starter --version

# --- Phase: 執筆に使うツール ---
# vs new が最後に呼ぶ doctor と同じもの。ここで入れておけば、vs new は確かめるだけで済む
echo "🧰 執筆に使うツール（Node・Vivliostyle・PDF や画像の処理など）をインストールしています…"
echo "   数分かかります。"
vivlio-starter doctor --fix --yes || echo "🟡 ツールの導入が途中で止まりました。新しいターミナルで vs doctor --fix を実行してください。"

echo ""
echo "✅ 準備ができました。新しいターミナルのウィンドウを開いて、次を打ってください:"
print -rn -- "  "; green "vs --version"; print -r -- ""
print -rn -- "  "; green "vs new mybook"; print -r -- ""
