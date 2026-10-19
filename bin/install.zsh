#!/usr/bin/env zsh
#
# install.zsh — macOS 向け Vivlio Starter の導入（Homebrew → Ruby → Vivlio Starter → ツール一式）
#
# - Homebrew が未導入なら確認のうえインストール（Xcode コマンドラインツールも一緒に入る）
# - Ruby 3.4 以上がすでにあれば、それを使う。無ければ（macOS 付属の 2.6 や rbenv の古い版）、
#   rbenv と ruby-build で最新の安定版を入れてグローバルに切り替える。Homebrew の古い Ruby は
#   brew upgrade で上げ、mise・rvm・asdf の古い Ruby は、その道具で上げるよう案内して止まる
# - bundler をインストール
# - Homebrew と rbenv の設定を書き込む（~/.zprofile か ~/.zshrc。同じ設定があれば足さない）
# - 尋ねること（Homebrew・設定の書き込み・プレビューの操作の許可・Kindle Previewer・パスワード）は
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

# Vivlio Starter が求める Ruby の版（gemspec の required_ruby_version。install_script_test が
# 一致を見張る）。これ以上の Ruby がすでにあれば、新しく組まずにそれを使う
MIN_RUBY="3.4"

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
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

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

# 設定ファイルに足す行。$( ) は書き込む先で展開させるので、ここでは展開しない
brew_setup_line() {
  print -r -- "eval \"\$($(brew_bin) shellenv)\""
}
rbenv_setup_line() {
  print -r -- 'eval "$(rbenv init - zsh)"'
}

# すでに同じ設定（コメントでない行）が ~/.zprofile か ~/.zshrc にあれば足さない。
# 手で書いた人の書き方（`brew shellenv zsh` など）とも重ならないよう、要の語で見る。
# ~/.zshrc も見るのは、rbenv 1.3 より前の案内どおり ~/.zshrc に書いている人が多いため
shell_config_has() {
  local file
  for file in "$ZPROFILE" "$ZSHRC"; do
    [[ -f "$file" ]] && grep -qE "^[^#]*($1)" "$file" && return 0
  done
  return 1
}

# rbenv の設定を書くファイル。rbenv 1.3 の `rbenv init` と同じく、~/.zshrc にすでに rbenv の
# 記述があればそちらに書き続け、無ければ ~/.zprofile に書く
rbenv_config_file() {
  if [[ -f "$ZSHRC" ]] && grep -q rbenv "$ZSHRC"; then
    print -r -- "$ZSHRC"
  else
    print -r -- "$ZPROFILE"
  fi
}

# 書き込む行（ファイルごと）。書くかどうかは最初に尋ね、書くのは Ruby を入れたあと
zprofile_lines=()
zshrc_lines=()
plan_setup_line() {
  if [[ "$1" == "$ZSHRC" ]]; then
    zshrc_lines+=("$2")
  else
    zprofile_lines+=("$2")
  fi
}

# 足す行と、足す先のファイルを並べる（書き込んだとき・足してもらうときの表示用）
show_setup_lines() {
  local file
  for file in ZPROFILE ZSHRC; do
    local -a lines
    if [[ $file == ZPROFILE ]]; then lines=("${zprofile_lines[@]}"); else lines=("${zshrc_lines[@]}"); fi
    (( ${#lines} > 0 )) || continue
    print -r -- "  ${${(P)file}/#$HOME/~}:"
    print -r -l -- "${lines[@]}" | sed 's/^/    /'
  done
}

# 今使われている Ruby を、何で入れたか（置き場所から判じる）
ruby_manager() {
  case "$1" in
    "") print -r -- none ;;
    /usr/bin/ruby) print -r -- system ;;
    */rbenv/*|*/.rbenv/*) print -r -- rbenv ;;
    */mise/*) print -r -- mise ;;
    */.asdf/*) print -r -- asdf ;;
    */.rvm/*) print -r -- rvm ;;
    */opt/ruby/bin/ruby) print -r -- homebrew ;;
    *) print -r -- other ;;
  esac
}

# 今の Ruby が、Vivlio Starter の求める版を満たすか（rbenv の入っていない版を指すときも偽）
ruby_new_enough() {
  ruby -e "exit(Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('$MIN_RUBY'))" >/dev/null 2>&1
}

# gem が入れたコマンド（vs）の置き場所に PATH が通っているか。rbenv・asdf・mise の shims は、
# 置き場所でなく shims から呼ぶので通っている扱い。Homebrew の Ruby は、既定では通っていない
# （brew info ruby の注意書き。通っていないと、gem は入っても vs が見つからない）
gem_bin_reachable() {
  [[ "$current_ruby" == */shims/* ]] && return 0
  local bindir
  bindir="$(ruby -e 'print Gem.bindir' 2>/dev/null)" || return 1
  [[ ":$PATH:" == *":$bindir:"* ]]
}

# gem を入れたあと、新しいコマンドを呼べるようにする（shims を作り直す道具では作り直す）
refresh_ruby_commands() {
  case "$manager" in
    rbenv) rbenv rehash ;;
    asdf) asdf reshim ruby ;;
    mise) mise reshim ;;
  esac 2>/dev/null || true
  rehash
}

# 今の Ruby をどう扱うかを決める（ruby_mode）
#   keep         … Ruby 3.4 以上がある。新しく組まずにそれを使う（ほかの仕事の Ruby を変えない）
#   rbenv        … Ruby が無い・macOS 付属・rbenv の古い版・-v で版を指定された。rbenv で入れる
#   brew_upgrade … Homebrew の古い Ruby。brew upgrade ruby で上げる
# mise・rvm・asdf などの古い Ruby は、案内して止まる（stop_for_old_ruby）
decide_ruby_mode() {
  current_ruby="$(command -v ruby 2>/dev/null || true)"
  current_ruby_version="$(ruby -e 'print RUBY_VERSION' 2>/dev/null || true)"
  manager="$(ruby_manager "$current_ruby")"
  if [[ "$VERSION" != "latest" ]]; then
    ruby_mode=rbenv
  elif [[ "$manager" != system && "$manager" != none ]] && ruby_new_enough; then
    ruby_mode=keep
  elif [[ "$manager" == homebrew ]]; then
    ruby_mode=brew_upgrade
  elif [[ "$manager" == system || "$manager" == none || "$manager" == rbenv ]]; then
    ruby_mode=rbenv
  else
    stop_for_old_ruby
  fi
}

# 古い Ruby を、rbenv 以外の道具（mise・rvm・asdf など）で入れている人への案内。
# 横に rbenv の Ruby を入れると Ruby が 2 つ並び、どちらが先に見つかるかが人によって
# 変わるので、その人が使っている道具で上げてもらう
stop_for_old_ruby() {
  echo "Ruby ${current_ruby_version}（${manager} で入れたもの）が使われています。Vivlio Starter には Ruby ${MIN_RUBY} 以上が要ります。" >&2
  echo "お使いの道具で Ruby を上げてから、もう一度このスクリプトを実行してください:" >&2
  case "$manager" in
    mise) echo "  mise use -g ruby@${FALLBACK_VERSION}" >&2 ;;
    rvm)  echo "  rvm install ${FALLBACK_VERSION} && rvm --default use ${FALLBACK_VERSION}" >&2 ;;
    asdf) echo "  asdf install ruby ${FALLBACK_VERSION} && asdf set --home ruby ${FALLBACK_VERSION}" >&2 ;;
    *)    echo "  （今の Ruby: ${current_ruby}）" >&2 ;;
  esac
  exit 1
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

  # 枠は青緑（Netlify の完了の枠のような色）。注意を促す vs の枠（黄色）と分け、
  # 導入を終えた歓迎だと見て取れるようにする。色を付けない端末では、枠も文字もそのまま
  local c="" g="" r="" none=""
  if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    c=$'\e[36m' g=$'\e[32m' r=$'\e[0m'
  fi

  print -r -- "${c}╭─ ${title} ${(l:width - 1 - ${(m)#title}::─:)none}╮${r}"
  local body pad
  for line in "${lines[@]}"; do
    pad=${(l:width - ${(m)#line}:: :)none}
    body=${line//vs new mybook/${g}vs new mybook${r}}
    body=${body//vs --help/${g}vs --help${r}}
    print -r -- "${c}│${r} ${body}${pad} ${c}│${r}"
  done
  print -r -- "${c}╰${(l:width + 2::─:)none}╯${r}"
}

is_macos=true
if [[ "$(uname -s)" != "Darwin" ]]; then
  is_macos=false
fi

echo "📚 Vivlio Starter を導入します（Homebrew・Ruby・Vivlio Starter・vivlio-starter-pdf・執筆に使うツール）。"
echo "   15 分ほどかかります。最初にいくつか確かめます。"
echo ""

# --- Phase: 今の Ruby ---
# 何も尋ねないうちに決める（古い Ruby の道具によっては、ここで案内して止まるため）
decide_ruby_mode

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
    echo "Ruby や gem を組むには Xcode コマンドラインツールが要ります。xcode-select --install で入れてから、もう一度実行してください。" >&2
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

if [[ "$ruby_mode" == brew_upgrade ]]; then
  if ! confirm "Homebrew の Ruby ${current_ruby_version} を最新版に上げますか？（Vivlio Starter には Ruby ${MIN_RUBY} 以上が要ります）"; then
    echo "Ruby を上げずに終了します。brew upgrade ruby で上げてから、もう一度実行してください。" >&2
    exit 1
  fi
fi

# 新しいターミナルで Homebrew・Ruby・vs を使うための設定。書かないと、新しいターミナルでは
# macOS 付属の Ruby 2.6 が使われ、gem install が /Library/Ruby/Gems に書けないという
# エラーで止まる（改善案.md #87。何も入っていない Mac で確かめた）
if $is_macos && ! shell_config_has 'brew shellenv'; then
  plan_setup_line "$ZPROFILE" "$(brew_setup_line)"
fi
if [[ "$ruby_mode" == rbenv ]] && ! shell_config_has 'rbenv init'; then
  plan_setup_line "$(rbenv_config_file)" "$(rbenv_setup_line)"
fi
# Homebrew の Ruby は gem のコマンドの置き場所に PATH を通す。上げると置き場所が変わる
# （…/gems/4.0.0/bin）ので、実際に足すかどうかと足す行は、Ruby を上げたあとで決める
add_gem_bin=false
if [[ "$ruby_mode" == brew_upgrade ]] || { [[ "$ruby_mode" == keep ]] && ! gem_bin_reachable; }; then
  add_gem_bin=true
fi

config_files=()
if (( ${#zprofile_lines} > 0 )) || $add_gem_bin; then
  config_files+=("~/.zprofile")
fi
if (( ${#zshrc_lines} > 0 )); then
  config_files+=("~/.zshrc")
fi
write_shell_config=false
if (( ${#config_files} > 0 )) && confirm "新しいターミナルで vs を使えるよう、${(j: と :)config_files} に設定を書き込みますか？"; then
  write_shell_config=true
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

  brew update
  if [[ "$ruby_mode" == rbenv ]]; then
    echo "📦 rbenv と ruby-build を確認しています…"
    # 入っていないものだけ入れ、古いものは上げる（ruby-build が古いと、最新の Ruby を知らない）。
    # 入っているものを brew install すると「already installed」の警告と `brew reinstall` の
    # 案内が出て、入れ直しているように読まれた（改善案.md #87）
    rbenv_install=() rbenv_upgrade=()
    for formula in rbenv ruby-build; do
      if ! brew list --formula --versions "$formula" >/dev/null 2>&1; then
        rbenv_install+=("$formula")
      elif [[ -n "$(brew outdated --formula --quiet "$formula" 2>/dev/null || true)" ]]; then
        rbenv_upgrade+=("$formula")
      fi
    done
    # Homebrew 7 から、端末では install のたびに [y/n] を尋ねる。入れることはもう決まっている
    if (( ${#rbenv_install} > 0 )); then
      HOMEBREW_NO_ASK=1 brew install "${rbenv_install[@]}" || true
    fi
    if (( ${#rbenv_upgrade} > 0 )); then
      HOMEBREW_NO_ASK=1 brew upgrade "${rbenv_upgrade[@]}" || true
    fi
  fi

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

# --- Phase: Ruby ---
if [[ "$ruby_mode" == keep ]]; then
  echo "💎 今の Ruby ${current_ruby_version} をそのまま使います（${MIN_RUBY} 以上）。"
elif [[ "$ruby_mode" == brew_upgrade ]]; then
  echo "💎 Homebrew の Ruby を最新版に上げています…"
  HOMEBREW_NO_ASK=1 brew upgrade ruby
  rehash
else
  # Ensure rbenv is on PATH for this session
  if [[ -x "$(brew --prefix 2>/dev/null)/bin/rbenv" ]]; then
    export PATH="$(brew --prefix)/bin:$PATH"
  fi

  if ! command -v rbenv >/dev/null 2>&1; then
    echo "PATH に rbenv が見つかりません。シェル初期化に rbenv の設定を追加してから再実行してください。" >&2
    echo "$(rbenv_config_file) に次の行を足してください:"
    rbenv_setup_line | sed 's/^/  /'
    exit 1
  fi

  eval "$(rbenv init - zsh)"

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
  manager=rbenv
fi

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
if $add_gem_bin && ! gem_bin_reachable; then
  zprofile_lines+=("export PATH=\"$(ruby -e 'print Gem.bindir'):\$PATH\"")
fi
if (( ${#zprofile_lines} + ${#zshrc_lines} == 0 )); then
  echo "シェルの設定は済んでいます。"
elif $write_shell_config; then
  (( ${#zprofile_lines} > 0 )) && print -r -l -- "" "# Vivlio Starter の install.zsh が追記" "${zprofile_lines[@]}" >> "$ZPROFILE"
  (( ${#zshrc_lines} > 0 )) && print -r -l -- "" "# Vivlio Starter の install.zsh が追記" "${zshrc_lines[@]}" >> "$ZSHRC"
  echo "次の設定を書き込みました:"
  show_setup_lines
else
  echo "シェルの設定には書き込みませんでした。使う前に、次の行を足してください:"
  show_setup_lines
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
# このシェルでも vs を呼べるようにする（Homebrew の Ruby は、gem のコマンドの置き場所に
# PATH が通っていない。設定ファイルに書いた行は、次のシェルから効く）
path=("$(ruby -e 'print Gem.bindir')" $path)
refresh_ruby_commands

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
# 設定を書き込まなかったときは、切り替えても vs が見つからないので切り替えない。
# 端末が無いとき（CI など）も切り替えない
if (( ${#zprofile_lines} + ${#zshrc_lines} == 0 )) || $write_shell_config; then
  if [[ -t 0 && -t 1 ]]; then
    exec zsh -l
  fi
  echo "新しいターミナルのウィンドウを開くと、vs を使えます。"
else
  echo "vs を使う前に、次の行を足して、新しいターミナルのウィンドウを開いてください:"
  show_setup_lines
fi
