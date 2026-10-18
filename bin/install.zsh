#!/usr/bin/env zsh
#
# install.zsh — macOS 向け Vivlio Starter の導入（Homebrew → Ruby → Vivlio Starter → ツール一式）
#
# - Homebrew が未導入なら確認のうえインストール（Xcode コマンドラインツールも一緒に入る）
# - rbenv と ruby-build を導入し、指定した Ruby をインストール（既定: 最新の安定版）
# - グローバルに切り替え、bundler をインストール
# - ~/.zprofile に Homebrew と rbenv の設定を書き込む（同じ設定があれば足さない）
# - 尋ねること（Homebrew・~/.zprofile・プレビューの操作の許可・Kindle Previewer・パスワード）は
#   最初にまとめる。あとは終わるまで席を外せる
# - Kindle を選んだ人には、Kindle Previewer と Rosetta 2 も入れる
# - Vivlio Starter と vivlio-starter-pdf（gem）を入れ、執筆に使うツール一式を
#   vivlio-starter doctor --fix で入れる
# - 最後にようこその枠を出し、端末から打ったときはそのウィンドウのまま vs を使えるようにする
#
# 使い方（Usage）:
#   bin/install.zsh                      # 対話モード、最新安定版を導入
#   bin/install.zsh -y                   # 非対話モード（自動確認）
#   bin/install.zsh -v 4.0.7             # 特定の Ruby バージョンを導入
#   bin/install.zsh --gem ./vivlio-starter.gem   # 手元の gem を入れる（公開前の確かめ用）
#   bin/install.zsh --pdf-gem ./vivlio-starter-pdf.gem   # vivlio-starter-pdf も手元の gem から
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
PDF_GEM_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      YES="true"; shift ;;
    -v|--version)
      VERSION="${2:-}"; shift 2 ;;
    --gem)
      GEM_FILE="${2:-}"; shift 2 ;;
    --pdf-gem)
      PDF_GEM_FILE="${2:-}"; shift 2 ;;
    --no-bundler)
      INSTALL_BUNDLER="false"; shift ;;
    -h|--help)
      cat <<USAGE
使い方: $0 [オプション]
  -y, --yes           非対話モードで実行し、確認を自動承認します
  -v, --version VER   インストールする Ruby のバージョン（既定: latest）。'latest' で自動解決
      --gem FILE      rubygems からでなく、手元の gem ファイルから Vivlio Starter を入れます
      --pdf-gem FILE  rubygems からでなく、手元の gem ファイルから vivlio-starter-pdf を入れます
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

# Kindle Previewer のアプリ（3 と 4 で名前が違う。doctor の KINDLE_PREVIEWER_APP_BINS と同じ）
kindle_previewer_installed() {
  [[ -d "/Applications/Kindle Previewer 4.app" || -d "/Applications/Kindle Previewer 3.app" ]]
}

# Kindle Previewer の変換部分は Intel 版なので、Apple シリコンの Mac には Rosetta 2 が要る
# （doctor の ROSETTA_RUNTIME と同じ実体で見る）
rosetta_needed() {
  [[ "$(uname -m)" == "arm64" && ! -e /Library/Apple/usr/libexec/oah/libRosettaRuntime ]]
}

# パスワードを覚えている状態（sudo の timestamp）を、導入が終わるまで延ばす。
# macOS の既定では 5 分で忘れ、Kindle Previewer や Homebrew が途中でまた尋ねる——
# 席を外した著者は気づかず、導入がそこで止まる（改善案.md #87）
sudo_keeper=""
start_sudo_keeper() {
  ( while true; do sudo -n -v 2>/dev/null || exit; sleep 50; kill -0 $$ 2>/dev/null || exit; done ) &
  sudo_keeper=$!
}

# 延ばすのをやめ、覚えているパスワードを忘れさせる。最後の exec では EXIT の trap が
# 走らないので、そこでも呼ぶ
stop_sudo_keeper() {
  if [[ -n "$sudo_keeper" ]]; then
    kill "$sudo_keeper" 2>/dev/null || true
    sudo_keeper=""
    sudo -k
  fi
}
trap stop_sudo_keeper EXIT

# ようこその枠。右端は zsh の ${(m)#…}（端末で占める桁数）でそろえる。
# 桁数は文字コードの設定に左右されるので、枠を組むあいだだけ UTF-8 にする。
# 打つもの（vs new mybook・vs --help）だけを緑にする（vs の Common.log_box と同じ形）
welcome_box() {
  local LC_ALL=en_US.UTF-8
  local title="💡 Vivlio Starter の世界へようこそ"
  local -a lines=("$@")
  local width=$(( ${(m)#title} + 2 )) line
  for line in "${lines[@]}"; do
    (( ${(m)#line} > width )) && width=${(m)#line}
  done

  # 枠は黄色（vs の枠の案内と同じ）。色を付けない端末では、枠も文字もそのまま
  local y="" g="" r="" none=""
  if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    y=$'\e[33m' g=$'\e[32m' r=$'\e[0m'
  fi

  print -r -- "${y}╭─ ${title} ${(l:width - 1 - ${(m)#title}::─:)none}╮${r}"
  local body pad
  for line in "${lines[@]}"; do
    pad=${(l:width - ${(m)#line}:: :)none}
    body=${line//vs new mybook/${g}vs new mybook${r}}
    body=${body//vs --help/${g}vs --help${r}}
    print -r -- "${y}│${r} ${body}${pad} ${y}│${r}"
  done
  print -r -- "${y}╰${(l:width + 2::─:)none}╯${r}"
}

is_macos=true
if [[ "$(uname -s)" != "Darwin" ]]; then
  is_macos=false
fi

echo "📚 Vivlio Starter を導入します（Homebrew・Ruby・Vivlio Starter・vivlio-starter-pdf・執筆に使うツール）。"
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

# Kindle 向けの本（KPF）は Kindle Previewer でしか作れない。500MB ほどあり、入れるのに
# パスワードも要るので、ここで尋ねて一緒に入れる。あとから targets に kindle を足した人には、
# vs build・vs preflight が vs doctor --fix を案内する（Build::KindlePreviewerNotice）
install_kindle=false
if $is_macos && ! kindle_previewer_installed; then
  echo "📱 Kindle 向けの電子書籍（KPF）は、Amazon の Kindle Previewer で作ります。"
  if confirm "Kindle Previewer もインストールしますか？（500MB ほど・あとからでも入れられます）"; then
    install_kindle=true
  fi
fi

# パスワードは、ここで 1 回だけ尋ねる。Homebrew のインストーラは、始める前にパスワードを
# 覚えている状態なら尋ね直さない（install.sh の have_sudo_access）。NONINTERACTIVE で
# 走らせ、RETURN も尋ねさせない。こうしておけば、尋ねることがすべて最初に集まる
if $install_homebrew || $install_kindle; then
  echo ""
  echo "🔑 インストールに、Mac の管理者のパスワード（ログインするときのもの）を使います。"
  echo "   打っても画面には表示されません。打ち終えたら RETURN（Enter）を押してください。"
  if ! sudo -v -p "   パスワード: "; then
    echo "パスワードを確かめられませんでした。もう一度このスクリプトを実行してください。" >&2
    exit 1
  fi
  start_sudo_keeper
fi

echo ""
echo "確認は以上です。終わるまで席を外して構いません。"
echo ""

# --- Phase: Homebrew・rbenv ---
if $is_macos; then
  echo "🍺 Homebrew を確認しています…"
  if $install_homebrew; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # インストーラの「Next steps」（~/.zprofile への書き込み）は、このあとこのスクリプトが行う
    echo "（Homebrew の「Next steps」は、このあとこのスクリプトが済ませます）"
  fi
  # このシェルで brew を使えるようにする（Apple シリコン・Intel のどちらでも）
  eval "$("$(brew_bin)" shellenv)"

  echo "📦 rbenv と ruby-build をインストールしています…"
  brew update
  # Homebrew 7 から、端末では install のたびに [y/n] を尋ねる。入れることはもう決まっている
  HOMEBREW_NO_ASK=1 brew install rbenv ruby-build || true

  # kindlepreviewer コマンド（アプリの中の CLI を呼ぶラッパー）は、あとの doctor --fix が作る
  if $install_kindle; then
    echo "📱 Kindle Previewer をインストールしています（500MB ほど）…"
    HOMEBREW_NO_ASK=1 brew install --cask kindle-previewer \
      || echo "🟡 Kindle Previewer を入れられませんでした。あとで、targets に kindle を足した本で vs doctor --fix を実行してください。"
    if rosetta_needed; then
      echo "🔁 Rosetta 2（Kindle Previewer の変換に要ります）をインストールしています…"
      sudo softwareupdate --install-rosetta --agree-to-license \
        || echo "🟡 Rosetta 2 を入れられませんでした。あとで sudo softwareupdate --install-rosetta --agree-to-license を実行してください。"
    fi
  fi
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
# PDF のしおり（目次）を付ける拡張。AGPL の HexaPDF を使うので別の gem に分けてあるが、
# 著者にはどちらも使ってほしいので、尋ねずに一緒に入れる。入らなくても本は作れる
echo "📄 vivlio-starter-pdf（PDF のしおりを付ける拡張）をインストールしています…"
gem install "${PDF_GEM_FILE:-vivlio-starter-pdf}" \
  || echo "🟡 vivlio-starter-pdf を入れられませんでした。PDF にしおりを付けるには、あとで gem install vivlio-starter-pdf を実行してください。"
rbenv rehash

echo "🔎 バージョン確認: vs --version"
# `vs` でなく正式名で呼ぶ。Vivliostyle CLI も `vs` という別名を入れるため（改善案.md #87）
version_line="$(vivlio-starter --version)"
print -r -- "$version_line"

# --- Phase: 執筆に使うツール ---
# vs new が最後に呼ぶ doctor と同じもの。ここで入れておけば、vs new は確かめるだけで済む
echo "🧰 執筆に使うツール（Node・Vivliostyle・PDF や画像の処理など）をインストールしています…"
echo "   数分かかります。"
vivlio-starter doctor --fix --yes || echo "🟡 ツールの導入が途中で止まりました。vs doctor --fix を実行してください。"
stop_sudo_keeper

# --- Phase: ようこそ ---
welcome_lines=(
  "Vivlio Starter バージョン ${version_line##* } がインストールされました。"
  ""
  "vs new mybook で新しい本を書き始めることができます。"
  "vs --help でコマンドの使い方を確認できます。"
  ""
  "素敵な一冊をどうぞ執筆なさってください。"
)
echo ""
welcome_box "${welcome_lines[@]}"
echo ""

# 新しいシェルに切り替え、このウィンドウのまま vs を使えるようにする。このスクリプトは
# 子のシェルで走るので、PATH や rbenv の設定を、打った人のシェルへ渡せない（Oh My Zsh と同じ形）。
# ~/.zprofile に設定が無いと、切り替えても vs が見つからないので、そのときは切り替えない。
# 端末が無いとき（CI など）も切り替えない
if (( ${#missing_lines} == 0 )) || $write_zprofile; then
  if [[ -t 0 && -t 1 ]]; then
    exec zsh -l
  fi
  echo "新しいターミナルのウィンドウを開くと、vs を使えます。"
else
  echo "vs を使う前に、~/.zprofile に次の行を足して、新しいターミナルのウィンドウを開いてください:"
  print -r -l -- "${missing_lines[@]}" | sed 's/^/  /'
fi
