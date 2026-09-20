# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/lint/line_link'

# ================================================================
# File: test/vivlio_starter/cli/lint/line_link_test.rb
# ================================================================
# 観点:
#   LL-1: compact は表示を行番号だけに保ち、飛び先は OSC 8 の URI 側に隠す
#   LL-2: path は素のテキスト（端末は画面の文字を見て開くため、エスケープを混ぜない）
#   LL-3: off と「端末でないとき」は素の数字——ファイルへ落ちたログにゴミを残さない
#   LL-4: 未知の設定値で校正を止めない
#
#   **素の数字に戻る経路をとくに見る。** ここが壊れると、パイプやリダイレクトで
#   受けたログにエスケープが紛れ、`vs lint > report.txt` の突き合わせが黙って狂う。
# ================================================================
class TestLineLink < Minitest::Test
  LL = VivlioStarter::CLI::Lint::LineLink

  # 端末に出している体で（tty? と設定を固定して）render を呼ぶ
  def render(line, path:, mode: 'compact')
    LL.stub(:linkable?, true) do
      LL.stub(:mode, mode) { LL.render(line, path: path) }
    end
  end

  # LL-1
  def test_compact_shows_only_the_number_and_hides_the_target
    out = render(223, path: 'contents/42-frontispiece.md')

    # 目に見える文字は行番号だけ（エスケープと URI を除くと "223" しか残らない）
    assert_equal '223', out.gsub(/\e\]8;;[^\e]*\e\\/, '').gsub(/\e\[[\d;]*m/, '')
    assert_includes out, "file://#{File.expand_path('contents/42-frontispiece.md')}:223"
    assert_includes out, LL::COLOR
    assert out.end_with?("\e]8;;\e\\"), 'リンクを閉じていないと、以降の出力まで同じリンクになる'
  end

  # LL-2
  def test_path_mode_is_plain_text
    out   = render(223, path: 'contents/42-frontispiece.md')
    plain = render(223, path: 'contents/42-frontispiece.md', mode: 'path')

    assert_equal 'contents/42-frontispiece.md:223', plain
    refute_includes plain, "\e", '素のテキストで出す方式なので、エスケープを混ぜない'
    refute_equal out, plain
  end

  # LL-3
  def test_off_mode_and_non_terminal_fall_back_to_plain_number
    assert_equal '223', render(223, path: 'contents/10-intro.md', mode: 'off')

    LL.stub(:linkable?, false) do
      LL.stub(:mode, 'compact') do
        assert_equal '223', LL.render(223, path: 'contents/10-intro.md')
      end
    end
  end

  # LL-3: 出力先が端末でなく配列（並列ビルド・構造化出力）のときはリンクにしない
  def test_emit_sink_disables_links
    previous = Thread.current[VivlioStarter::CLI::Common::EMIT_SINK_KEY]
    Thread.current[VivlioStarter::CLI::Common::EMIT_SINK_KEY] = []

    refute LL.linkable?, '溜める先は端末ではないので、エスケープを混ぜない'
  ensure
    Thread.current[VivlioStarter::CLI::Common::EMIT_SINK_KEY] = previous
  end

  # LL-3: パスが無ければ飛び先を作れない
  def test_missing_path_falls_back_to_plain_number
    LL.stub(:linkable?, true) { assert_equal '223', LL.render(223, path: nil) }
  end

  # LL-4
  def test_unknown_mode_falls_back_to_compact
    assert_equal 'compact', LL.normalize('いろいろ')
    assert_equal 'compact', LL.normalize('')
    assert_equal 'path',    LL.normalize('path')
  end

  # NO_COLOR は色だけを外す（リンクは残す——押せるかどうかは色の話ではない）
  def test_no_color_keeps_the_link
    original = ENV.fetch('NO_COLOR', nil)
    ENV['NO_COLOR'] = '1'
    out = render(223, path: 'contents/10-intro.md')

    refute_includes out, LL::COLOR
    assert_includes out, 'file://'
  ensure
    ENV['NO_COLOR'] = original
  end
end
