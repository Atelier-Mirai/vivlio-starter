# frozen_string_literal: true

require_relative '../test_helper'

# ================================================================
# bin/install-ruby.zsh と対応 Ruby バージョンの一致
# ================================================================
# スクリプトの FALLBACK_VERSION は「最新の Ruby」ではなく
# **本プロジェクトが実際に試験している版**でなければならない。自動解決に
# 失敗した人だけが未検証の Ruby を掴む、という状態を避けるため。
#
# 実際に外れていた: Rakefile と 92 章は 3.4.10 / 4.0.6 へ更新済みだったのに、
# スクリプトだけ 4.0.2 のまま取り残されていた（2026-08-10 に発見）。
# 原稿とコードは目に付くがシェルスクリプトは見落とす——機械に見張らせる。
class InstallRubyScriptTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SCRIPT = File.join(ROOT, 'bin', 'install-ruby.zsh')

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
                    "bin/install-ruby.zsh の FALLBACK_VERSION (#{fallback}) が " \
                    "Rakefile の SUPPORTED_RUBY_VERSIONS (#{supported_versions.join(' / ')}) にありません。" \
                    '未検証の Ruby を配ることになります。'
  end

  # 使い方の例に書くバージョンも、実在する対応版にする
  # （読者はここをそのままコピーする）
  def test_should_show_a_supported_version_in_the_usage_example
    examples = @script.scan(/install-ruby\.zsh\s+-v\s+(\d+\.\d+\.\d+)/).flatten

    refute_empty examples, '使い方の例にバージョン指定が見当たりません'
    examples.each do |version|
      assert_includes supported_versions, version,
                      "使い方の例の #{version} が対応バージョンにありません"
    end
  end
end
