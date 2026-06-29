# frozen_string_literal: true

# ================================================================
# Test: textlint_formatter_test.rb
# ================================================================
# テスト対象:
#   TextlintFormatter（lib/vivlio_starter/cli/textlint_formatter.rb）
#
# 検証内容:
#   - aggregate_json: textlint --format json のルール単位集約・無効化・sentence-length 要約
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/textlint_formatter'

module VivlioStarter
  module CLI
    # TextlintFormatter のユニットテスト
    class TextlintFormatterTest < Minitest::Test
      # ================================================================
      # aggregate_json テスト（ルール単位の集約）
      # ================================================================

      def sample_json
        <<~JSON
          [
            { "filePath": "/proj/contents/31-lint.md", "messages": [
              { "ruleId": "ja-spacing/ja-space-around-code", "message": "インラインコードの後にスペースを入れません。", "line": 39 },
              { "ruleId": "ja-spacing/ja-space-around-code", "message": "インラインコードの後にスペースを入れません。", "line": 75 },
              { "ruleId": "prh", "message": "以下の => 次の\\n書籍の場合は…", "line": 84, "fix": { "text": "次の" } },
              { "ruleId": "prh", "message": "以下の => 次の\\n書籍の場合は…", "line": 122, "fix": { "text": "次の" } },
              { "ruleId": "prh", "message": "全て => すべて", "line": 31 }
            ] }
          ]
        JSON
      end

      # 同じ指摘（メッセージ先頭行＋ルール）を 1 行へ集約し、件数降順に並べる
      def test_aggregate_json_groups_and_sorts
        result = TextlintFormatter.aggregate_json(sample_json, base_dir: '/proj')

        assert_equal 5, result[:total], '総指摘数'
        assert_equal 2, result[:fixable], 'fix を持つ指摘数（prh 2 件）'
        file = result[:files].first
        assert_equal 'contents/31-lint.md', file[:path], 'base_dir 相対のパス'

        top = file[:rows].first
        assert_equal 2, top[:count], '件数の多い指摘が先頭'
        assert_equal '[ja-space-around-code] インラインコードの後にスペースを入れません。', top[:label]
        assert_equal '39, 75', top[:lines]
        # prh は置換（先頭行）単位で別グループ
        labels = file[:rows].map { it[:label] }
        assert_includes labels, '[prh] 以下の => 次の'
        assert_includes labels, '[prh] 全て => すべて'
      end

      # disabled_rules で指定したルールの指摘が除外される
      def test_aggregate_json_disabled_rules
        result = TextlintFormatter.aggregate_json(sample_json, base_dir: '/proj',
                                                  disabled_rules: ['ja-space-around-code'])
        labels = result[:files].first[:rows].map { it[:label] }
        refute(labels.any? { it.include?('ja-space-around-code') }, '無効化したルールは出ない')
        assert(labels.any? { it.include?('[prh]') }, '他のルールは残る')
      end

      # disabled_terms で指定した語を含む "X => Y" 指摘が除外される
      def test_aggregate_json_disabled_terms
        result = TextlintFormatter.aggregate_json(sample_json, base_dir: '/proj',
                                                  disabled_terms: ['次の'])
        labels = result[:files].first[:rows].map { it[:label] }
        refute(labels.any? { it.include?('以下の => 次の') }, '指定語の指摘は消える')
        assert(labels.any? { it.include?('全て => すべて') }, '別の表記揺れは残る')
      end

      # trim_long_vowel で「X => Xー」（末尾長音追加）系の指摘が抑止される
      def test_aggregate_json_trim_long_vowel
        json = <<~JSON
          [{ "filePath": "/p/a.md", "messages": [
            { "ruleId": "prh", "message": "パラメータ => パラメーター", "line": 5 },
            { "ruleId": "prh", "message": "以下の => 次の", "line": 9 }
          ] }]
        JSON
        labels = TextlintFormatter.aggregate_json(json, base_dir: '/p', trim_long_vowel: true)[:files].first[:rows].map { it[:label] }
        refute(labels.any? { it.include?('パラメーター') }, '末尾長音を足す指摘は抑止される')
        assert(labels.any? { it.include?('以下の => 次の') }, '長音以外の表記揺れは残る')
      end

      # 「X => Xー」判定の境界
      def test_long_vowel_addition_detection
        assert TextlintFormatter.long_vowel_addition?('サーバ => サーバー')
        assert TextlintFormatter.long_vowel_addition?('パラメータ => パラメーター')
        refute TextlintFormatter.long_vowel_addition?('以下の => 次の')
        refute TextlintFormatter.long_vowel_addition?('インラインコードの後にスペースを入れません。')
      end

      # 出現ごとに数値が変わるルール（sentence-length）は要約ラベルで 1 つに畳む
      def test_aggregate_json_summarizes_sentence_length
        json = <<~JSON
          [{ "filePath": "/proj/a.md", "messages": [
            { "ruleId": "sentence-length", "message": "Line 1 sentence length(156) exceeds the maximum sentence length of 100.", "line": 5 },
            { "ruleId": "sentence-length", "message": "Line 2 sentence length(102) exceeds the maximum sentence length of 100.", "line": 9 }
          ] }]
        JSON
        rows = TextlintFormatter.aggregate_json(json, base_dir: '/proj')[:files].first[:rows]
        assert_equal 1, rows.size, '1 行に集約される'
        assert_equal 2, rows.first[:count]
        assert_equal '[sentence-length] 一文が長すぎます（最大文長を超過）', rows.first[:label]
      end

      # 不正な JSON は nil を返す（呼び出し側が生出力へフォールバックする）
      def test_aggregate_json_returns_nil_on_invalid
        assert_nil TextlintFormatter.aggregate_json('not json')
      end

      # 指摘ゼロのファイルは files に含めない
      def test_aggregate_json_skips_files_without_messages
        json = '[{ "filePath": "/proj/a.md", "messages": [] }]'
        result = TextlintFormatter.aggregate_json(json, base_dir: '/proj')
        assert_empty result[:files]
        assert_equal 0, result[:total]
      end
    end
  end
end
