# frozen_string_literal: true

require_relative '../test_helper'
require 'vivlio_starter/cli/common'

# ================================================================
# bin/install.zsh と対応 Ruby バージョンの一致
# ================================================================
# スクリプトの FALLBACK_VERSION は「最新の Ruby」ではなく
# **本プロジェクトが実際に試験している版**でなければならない。自動解決に
# 失敗した人だけが未検証の Ruby を掴む、という状態を避けるため。
#
# 実際に外れていた: Rakefile と 92 章は 3.4.10 / 4.0.6 へ更新済みだったのに、
# スクリプトだけ 4.0.2 のまま取り残されていた（2026-08-10 に発見）。
# 原稿とコードは目に付くがシェルスクリプトは見落とす——機械に見張らせる。
class InstallScriptTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SCRIPT = File.join(ROOT, 'bin', 'install.zsh')

  def setup
    skip "#{SCRIPT} が見つかりません" unless File.exist?(SCRIPT)

    @script = File.read(SCRIPT, encoding: 'utf-8')
  end

  # Rakefile が持つ対応バージョン表（テストの正典）
  def supported_versions
    rakefile = File.read(File.join(ROOT, 'Rakefile'), encoding: 'utf-8')
    rakefile[/SUPPORTED_RUBY_VERSIONS\s*=\s*%w\[([^\]]*)\]/, 1].to_s.split
  end

  def test_should_pin_fallback_version_to_a_supported_ruby
    fallback = @script[/^FALLBACK_VERSION="([^"]+)"/, 1]

    refute_nil fallback, 'FALLBACK_VERSION が読み取れません'
    assert_includes supported_versions, fallback,
                    "bin/install.zsh の FALLBACK_VERSION (#{fallback}) が " \
                    "Rakefile の SUPPORTED_RUBY_VERSIONS (#{supported_versions.join(' / ')}) にありません。" \
                    '未検証の Ruby を配ることになります。'
  end

  # ~/.zprofile に書く行は、$( ) を展開せずにそのまま書く。
  # 以前は推奨設定を "…$(brew shellenv)…" と二重引用符で表示していたため、
  # 表示の時点で展開され、写して貼ると .zprofile が壊れる形で出ていた（改善案.md #87）。
  def test_should_write_shell_setup_lines_without_expanding_them
    skip 'zsh がありません' unless system('command -v zsh >/dev/null 2>&1')

    functions = @script[/^brew_bin\(\) \{.*?^\}\n.*?^shell_setup_lines\(\) \{.*?^\}\n/m]
    refute_nil functions, 'brew_bin と shell_setup_lines が読み取れません'

    lines = IO.popen(['zsh', '-c', "#{functions}\nshell_setup_lines"], &:read).lines(chomp: true)

    assert_match %r{\Aeval "\$\(/(opt/homebrew|usr/local)/bin/brew shellenv\)"\z}, lines[0]
    assert_equal 'eval "$(rbenv init - zsh)"', lines[1]
  end

  # ようこその枠は、右端の │ がそろう（全角と絵文字を 2 桁と数える。vs の Common.log_box と同じ）。
  # スクリプトと同じ set -u の下で走らせる（名前の無い ${(l:…:)} が「parameter not set」で落ちた）
  def test_should_align_the_right_edge_of_the_welcome_box
    skip 'zsh がありません' unless system('command -v zsh >/dev/null 2>&1')

    function = @script[/^welcome_box\(\) \{.*?^\}\n/m]
    refute_nil function, 'welcome_box が読み取れません'

    call = "welcome_box 'Vivlio Starter バージョン 1.0.0 がインストールされました。' '' " \
           "'vs new mybook で新しい本を書き始めることができます。' 'ok'"
    rows = IO.popen(['zsh', '-c', "set -euo pipefail\n#{function}\n#{call}"], &:read).force_encoding('utf-8').lines(chomp: true)

    assert_equal 6, rows.size
    widths = rows.map { VivlioStarter::CLI::Common.display_width(it) }
    assert_equal [widths.first], widths.uniq, "枠の幅がそろっていません:\n#{rows.join("\n")}"
    refute rows.join.include?("\e["), '端末でないときは色を付けない'
  end

  # 最後の exec では EXIT の trap が走らない。パスワードを覚えさせ続ける裏の処理は、
  # 切り替える前に止める（止めないと、切り替えた先のシェルで延ばし続ける）
  def test_should_stop_keeping_sudo_alive_before_switching_shells
    stop = @script.rindex(/^stop_sudo_keeper$/)
    switch = @script.index('exec zsh -l')

    refute_nil switch, 'exec zsh -l が見当たりません'
    refute_nil stop, 'stop_sudo_keeper を呼んでいません'
    assert_operator stop, :<, switch
  end

  # 使い方の例に書くバージョンも、実在する対応版にする
  # （読者はここをそのままコピーする）
  def test_should_show_a_supported_version_in_the_usage_example
    examples = @script.scan(/install\.zsh\s+-v\s+(\d+\.\d+\.\d+)/).flatten

    refute_empty examples, '使い方の例にバージョン指定が見当たりません'
    examples.each do |version|
      assert_includes supported_versions, version,
                      "使い方の例の #{version} が対応バージョンにありません"
    end
  end
end
