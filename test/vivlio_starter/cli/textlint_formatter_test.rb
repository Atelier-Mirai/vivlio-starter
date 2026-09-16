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

      # 行単位の抑止（`<!-- vs-lint-disable-next-line -->` の次の行）。
      # textlint 側の comments フィルタが -next-line を実装していないため、
      # 出力段で落とすしかない。**集約の前に当たること**が要点で、集約後は
      # 行番号が 1 行へ畳まれて選り分けられなくなる
      def test_aggregate_json_suppresses_listed_lines
        result = TextlintFormatter.aggregate_json(
          sample_json, base_dir: '/proj',
          suppressed_lines: { '/proj/contents/31-lint.md' => Set[39, 84] }
        )

        assert_equal 3, result[:total], '抑止した 2 件は数にも入らない'
        rows = result[:files].first[:rows]
        assert_equal '75', rows.find { it[:label].include?('ja-space-around-code') }[:lines],
                     '同じルールでも抑止していない行は残る'
        assert_equal '122', rows.find { it[:label].include?('以下の') }[:lines]
      end

      # 抑止対象が全部消えたファイルは、そもそも表示しない
      def test_aggregate_json_drops_files_fully_suppressed
        result = TextlintFormatter.aggregate_json(
          sample_json, base_dir: '/proj',
          suppressed_lines: { '/proj/contents/31-lint.md' => Set[31, 39, 75, 84, 122] }
        )

        assert_equal 0, result[:total]
        assert_empty result[:files]
      end

      # 別ファイルの抑止行が漏れて効かないこと（パスをキーに引く）
      def test_aggregate_json_scopes_suppression_by_file
        result = TextlintFormatter.aggregate_json(
          sample_json, base_dir: '/proj',
          suppressed_lines: { '/proj/contents/99-other.md' => Set[39, 75, 84, 122, 31] }
        )

        assert_equal 5, result[:total], '他ファイルの抑止行は当てない'
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

      # 件数が同じルールは、最初の出現行の早い順に並ぶ（著者は原稿を上から直すため）。
      # sort_by は安定ではないので、第 2 キーが無いと同数の行の並びが実行ごとに変わる
      def test_aggregate_json_breaks_count_ties_by_first_line
        json = <<~JSON
          [{ "filePath": "/proj/a.md", "messages": [
            { "ruleId": "prh", "message": "遅い => おそい", "line": 200 },
            { "ruleId": "prh", "message": "遅い => おそい", "line": 210 },
            { "ruleId": "prh", "message": "早い => はやい", "line": 10 },
            { "ruleId": "prh", "message": "早い => はやい", "line": 20 },
            { "ruleId": "prh", "message": "速い => はやい", "line": 100 },
            { "ruleId": "prh", "message": "速い => はやい", "line": 110 }
          ] }]
        JSON
        rows = TextlintFormatter.aggregate_json(json, base_dir: '/proj')[:files].first[:rows]

        assert_equal [2, 2, 2], rows.map { it[:count] }, '3 つとも同数'
        assert_equal ['10, 20', '100, 110', '200, 210'], rows.map { it[:lines] }, '同数なら出現行の早い順'
      end

      # no-mix-dearu-desumasu は表示文を置き換える。判定の実態は「である」で終わる文だけなのに、
      # 元の文言は「"である"調」と広く聞こえ、先頭の「箇条書き:」で箇条書き専用にも見えるため。
      # 場所（本文・箇条書き）とプリセットの違いは区別せず、1 行に畳む
      def test_aggregate_json_relabels_no_mix_dearu_desumasu
        json = <<~JSON
          [{ "filePath": "/proj/a.md", "messages": [
            { "ruleId": "japanese/no-mix-dearu-desumasu", "message": "本文: である調 と ですます調 が混在", "line": 3 },
            { "ruleId": "japanese/no-mix-dearu-desumasu", "message": "箇条書き: である調 と ですます調 が混在", "line": 8 },
            { "ruleId": "ja-technical-writing/no-mix-dearu-desumasu", "message": "箇条書き: である調 でなければなりません", "line": 9 }
          ] }]
        JSON
        rows = TextlintFormatter.aggregate_json(json, base_dir: '/proj')[:files].first[:rows]

        assert_equal 1, rows.size, '場所とプリセットの違いを問わず 1 行に畳む'
        assert_equal '[no-mix-dearu-desumasu] 「である」と「です・ます」が混在しています。', rows.first[:label]
        assert_equal 3, rows.first[:count]
        assert_equal '3, 8, 9', rows.first[:lines]
      end

      # 冗長表現の指摘に付く `【dict2】`（ルール内部のパターン番号）は落とす。
      # 同じ指摘が別のパターン番号で出ることはないので、集約の単位は変わらない
      def test_aggregate_json_drops_dictionary_tag
        json = <<~JSON
          [{ "filePath": "/proj/a.md", "messages": [
            { "ruleId": "ja-technical-writing/ja-no-redundant-expression",
              "message": "【dict2】 \\"することもできます\\"は冗長な表現です。\\n解説: https://example.com#dict2", "line": 73 }
          ] }]
        JSON
        rows = TextlintFormatter.aggregate_json(json, base_dir: '/proj')[:files].first[:rows]

        assert_equal '[ja-no-redundant-expression] "することもできます"は冗長な表現です。', rows.first[:label]
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
