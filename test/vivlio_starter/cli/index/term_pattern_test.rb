# frozen_string_literal: true

# ================================================================
# Test: term_pattern_test.rb
# ================================================================
# テスト対象:
#   TermPattern — 辞書エントリを照合用 Regexp にする、綴りの唯一の解釈。
#
# 検証内容:
#   - 辞書の `\b` は ASCII の語境界として読む（日本語が続いても当たる）
#   - 英字どうしの食い込みは従来どおり弾く
#   - pattern を持たない語・壊れた pattern の語は完全一致へ落ちる
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/index/term_pattern'

module VivlioStarter
  module CLI
    module IndexCommands
      class TermPatternTest < Minitest::Test
        # 和語がくっついた形でも語を拾う。Ruby の `\b` は日本語を語構成文字として
        # 扱うため、素の /\bCMYK\b/ は「CMYK版」に当たらない
        def test_ascii_term_matches_when_japanese_follows
          pattern = TermPattern.for({ 'term' => 'CMYK', 'pattern' => '/\bCMYK\b/' })

          assert_match pattern, '印刷用PDF（CMYK版）のサイズ'
          assert_match pattern, 'CMYK は印刷向けの色空間です'
          assert_match pattern, '本書のCMYKについて'
        end

        # 英字どうしの食い込みは弾く（MATTR の中の TTR を拾わない）
        def test_ascii_term_does_not_match_inside_another_ascii_word
          refute_match TermPattern.for({ 'term' => 'TTR', 'pattern' => '/\bTTR\b/' }), 'MATTR は指標です'
          refute_match TermPattern.for({ 'term' => 'CSS', 'pattern' => '/\bCSS\b/' }), 'CSS3 の新機能'
          refute_match TermPattern.for({ 'term' => 'Git', 'pattern' => '/\bGit\b/' }), 'GitHub を使う'
        end

        # 日本語の語は `\b` が付かないので、そのまま部分一致で当たる
        def test_japanese_term_matches_as_substring
          pattern = TermPattern.for({ 'term' => 'マスター', 'pattern' => '/マスター/' })

          assert_match pattern, 'マスター画像を配置します'
        end

        # pattern が無ければ用語そのものの完全一致
        def test_entry_without_pattern_falls_back_to_literal
          pattern = TermPattern.for({ 'term' => 'PDF/X-1a' })

          assert_match pattern, '入稿は PDF/X-1a です'
        end

        # 壊れた pattern で走査全体を止めない
        def test_broken_pattern_falls_back_to_literal
          pattern = TermPattern.for({ 'term' => 'CMYK', 'pattern' => '/[/' })

          assert_match pattern, 'CMYK 版'
        end
      end
    end
  end
end
