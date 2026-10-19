# frozen_string_literal: true

require_relative '../test_helper'
require 'tmpdir'
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

  # 求める Ruby の版は gemspec の required_ruby_version と同じにする。
  # これ以上の Ruby がある人には、新しく組まずにそれを使う
  def test_should_require_the_same_ruby_as_the_gemspec
    gemspec = File.read(File.join(ROOT, 'vivlio-starter.gemspec'), encoding: 'utf-8')

    assert_equal gemspec[/required_ruby_version\s*=\s*'>= ([\d.]+)'/, 1], @script[/^MIN_RUBY="([^"]+)"/, 1]
  end

  # 設定ファイルに書く行は、$( ) を展開せずにそのまま書く。
  # 以前は推奨設定を "…$(brew shellenv)…" と二重引用符で表示していたため、
  # 表示の時点で展開され、写して貼ると .zprofile が壊れる形で出ていた（改善案.md #87）。
  def test_should_write_shell_setup_lines_without_expanding_them
    lines = zsh(<<~ZSH).lines(chomp: true)
      #{functions(:brew_bin, :brew_setup_line, :rbenv_setup_line)}
      brew_setup_line
      rbenv_setup_line
    ZSH

    assert_match %r{\Aeval "\$\(/(opt/homebrew|usr/local)/bin/brew shellenv\)"\z}, lines[0]
    assert_equal 'eval "$(rbenv init - zsh)"', lines[1]
  end

  # rbenv の設定は、~/.zshrc にすでに rbenv の記述があればそちらに書き続け、無ければ
  # ~/.zprofile に書く（rbenv 1.3 の rbenv init と同じ）。すでにあるかは両方のファイルで見る
  def test_should_keep_writing_rbenv_setup_to_zshrc_when_it_is_already_there
    Dir.mktmpdir do |dir|
      probe = <<~ZSH
        ZPROFILE=#{dir}/.zprofile ZSHRC=#{dir}/.zshrc
        #{functions(:rbenv_config_file, :shell_config_has)}
        print -r -- "$(rbenv_config_file)"
        shell_config_has 'rbenv init' && print has || print missing
      ZSH

      assert_equal ["#{dir}/.zprofile", 'missing'], zsh(probe).lines(chomp: true)

      File.write(File.join(dir, '.zshrc'), %(# eval "$(rbenv init - zsh)"\n))
      assert_equal ["#{dir}/.zshrc", 'missing'], zsh(probe).lines(chomp: true), 'コメントの行は設定に数えない'

      File.write(File.join(dir, '.zshrc'), %(eval "$(rbenv init - zsh)"\n))
      assert_equal ["#{dir}/.zshrc", 'has'], zsh(probe).lines(chomp: true)
    end
  end

  # 今の Ruby の版と置き場所から、そのまま使うか・rbenv で入れるか・Homebrew で上げるかを決める。
  # mise・rvm・asdf の古い Ruby は、横に rbenv の Ruby を並べず、その道具での上げ方を案内して止まる
  def test_should_decide_how_to_get_ruby_from_the_current_one
    assert_equal 'rbenv', ruby_mode_for('.rbenv/shims/ruby', '3.3.6')
    assert_equal 'keep', ruby_mode_for('.rbenv/shims/ruby', '3.4.7')
    assert_equal 'keep', ruby_mode_for('.local/share/mise/installs/ruby/3.4.7/bin/ruby', '3.4.7')
    assert_equal 'keep', ruby_mode_for('opt/homebrew/opt/ruby/bin/ruby', '4.0.1')
    assert_equal 'brew_upgrade', ruby_mode_for('opt/homebrew/opt/ruby/bin/ruby', '3.3.6')
    assert_equal 'rbenv', ruby_mode_for('.local/share/mise/installs/ruby/3.4.7/bin/ruby', '3.4.7', version: '4.0.7'),
                 '-v で版を指定されたら rbenv で入れる'

    stopped = ruby_mode_for('.local/share/mise/installs/ruby/3.3.6/bin/ruby', '3.3.6')
    assert_includes stopped, 'mise use -g ruby@4.0.7'
    assert_includes stopped, 'exit=1'
    assert_includes ruby_mode_for('.rvm/rubies/ruby-3.3.6/bin/ruby', '3.3.6'), 'rvm install'
  end

  def test_should_install_with_rbenv_over_the_ruby_that_comes_with_macos
    skip '/usr/bin/ruby がありません' unless File.executable?('/usr/bin/ruby')

    assert_equal 'rbenv', zsh("#{decide_ruby_mode_code}\ndecide_ruby_mode; print -r -- $ruby_mode", path: '/usr/bin:/bin')
  end

  # Homebrew の Ruby は、gem のコマンドの置き場所に PATH が通っていない（vs が見つからない）。
  # shims から呼ぶ道具（rbenv・asdf・mise）は、置き場所でなく shims に PATH が通っていればよい
  def test_should_tell_whether_gem_commands_are_on_the_path
    Dir.mktmpdir do |dir|
      fake = File.join(dir, "ruby")
      File.write(fake, "#!/bin/sh\nexec '#{RbConfig.ruby}' \"$@\"\n")
      File.chmod(0o755, fake)
      code = ->(current) { "#{functions(:gem_bin_reachable)}\ncurrent_ruby=#{current}\ngem_bin_reachable && print yes || print no" }

      assert_equal "no", zsh(code.("/opt/homebrew/opt/ruby/bin/ruby"), path: "#{dir}:/usr/bin:/bin")
      assert_equal "yes", zsh(code.("/opt/homebrew/opt/ruby/bin/ruby"), path: "#{dir}:#{Gem.bindir}:/usr/bin:/bin")
      assert_equal "yes", zsh(code.("/Users/a/.rbenv/shims/ruby"), path: "#{dir}:/usr/bin:/bin")
    end
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

  private

  # スクリプトから関数の定義を取り出す
  def functions(*names)
    names.map do |name|
      @script[/^#{name}\(\) \{\n.*?^\}\n/m] || flunk("#{name} が読み取れません")
    end.join
  end

  # スクリプトと同じ set -euo pipefail の下で zsh を走らせ、出力と（失敗なら）終了コードを返す
  def zsh(code, path: ENV.fetch('PATH'))
    skip 'zsh がありません' unless system('command -v zsh >/dev/null 2>&1')

    out = IO.popen({ 'PATH' => path }, ['zsh', '-c', "set -euo pipefail\n#{code}"], err: %i[child out], &:read)
    out = out.force_encoding('utf-8').chomp
    Process.last_status.success? ? out : "#{out}\nexit=#{Process.last_status.exitstatus}"
  end

  def decide_ruby_mode_code(version: 'latest')
    <<~ZSH
      VERSION=#{version} MIN_RUBY=#{@script[/^MIN_RUBY="([^"]+)"/, 1]} FALLBACK_VERSION=#{@script[/^FALLBACK_VERSION="([^"]+)"/, 1]}
      #{functions(:ruby_manager, :ruby_new_enough, :stop_for_old_ruby, :decide_ruby_mode)}
    ZSH
  end

  # relative の置き場所に、版が ruby_version の偽の ruby を置き、ruby_mode を決めさせる
  def ruby_mode_for(relative, ruby_version, version: 'latest')
    Dir.mktmpdir do |dir|
      fake = File.join(dir, relative)
      FileUtils.mkdir_p(File.dirname(fake))
      prelude = File.join(dir, 'fake_version.rb')
      File.write(prelude, "Object.send(:remove_const, :RUBY_VERSION)\nRUBY_VERSION = '#{ruby_version}'\n")
      File.write(fake, "#!/bin/sh\nexec '#{RbConfig.ruby}' -W0 -r'#{prelude}' \"$@\"\n")
      File.chmod(0o755, fake)

      zsh("#{decide_ruby_mode_code(version:)}\ndecide_ruby_mode; print -r -- $ruby_mode",
          path: "#{File.dirname(fake)}:/usr/bin:/bin")
    end
  end
end
