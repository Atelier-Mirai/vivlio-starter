# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/index/manuscript_markup'

module VivlioStarter
  module CLI
    module IndexCommands
      # 原稿の手動登録の印を探して外す（index-glossary-registration-spec.md §3.1.3）
      class ManuscriptMarkupTest < Minitest::Test
        def setup
          @dir = Dir.mktmpdir('manuscript_markup_test')
          @path = File.join(@dir, '11-intro.md')
          File.write(@path, <<~MD)
            # はじめに

            最初に[セットアップ]を済ませます。[セットアップ|せっとあっぷ]は一度だけです。
            記法は `[セットアップ]` のように書きます。[セットアップ](https://example.com) も参照。

            ```markdown
            [セットアップ]
            ```
          MD
        end

        def teardown = FileUtils.rm_rf(@dir)

        def test_places_lists_only_markup_outside_code_and_links
          assert_equal ['11-intro:3', '11-intro:3'], ManuscriptMarkup.places('セットアップ', [@path])
        end

        def test_strip_leaves_the_term_and_keeps_code_and_links
          count = ManuscriptMarkup.strip!('セットアップ', [@path])
          text = File.read(@path)

          assert_equal 2, count
          assert_includes text, '最初にセットアップを済ませます。セットアップは一度だけです。'
          assert_includes text, '`[セットアップ]` のように'
          assert_includes text, '[セットアップ](https://example.com)'
          assert_includes text, "```markdown\n[セットアップ]\n```"
        end

        def test_strip_does_not_touch_other_terms
          File.write(@path, "[Ruby]と[セットアップ]です。\n")

          ManuscriptMarkup.strip!('セットアップ', [@path])

          assert_equal "[Ruby]とセットアップです。\n", File.read(@path)
        end

        # --- 綴りを直したときの原稿の書き換え（改善案 #103） ---

        # 古い綴りは空白の揺れごと数える。コードの中・新しい綴り・英数字の語の途中は数えない
        def test_spelling_places_lists_old_spellings_outside_code
          File.write(@path, <<~MD)
            # ラベルIDの扱い

            ラベルID を付けます。ラベル ID も同じです。`ラベルID` はコードです。
            すでに ラベル id と書いた箇所もあります。

            ```markdown
            ラベルID
            ```
          MD

          assert_equal [['11-intro:1', 'ラベルID'], ['11-intro:3', 'ラベルID'], ['11-intro:3', 'ラベル ID']],
                       ManuscriptMarkup.spelling_places('ラベルID', 'ラベル id', [@path])
        end

        def test_respell_rewrites_old_spellings_and_keeps_code
          File.write(@path, "ラベルID と ラベル ID と `ラベルID` と [ラベルID|らべるID]。\n")

          count = ManuscriptMarkup.respell!('ラベルID', 'ラベル id', [@path])

          assert_equal 3, count
          assert_equal "ラベル id と ラベル id と `ラベルID` と [ラベル id|らべるID]。\n", File.read(@path)
        end

        # 「Type 3」を直しても「Type 30」は残る
        def test_respell_does_not_touch_longer_words
          File.write(@path, "Type 3 と Type 30 と Type 3D。\n")

          ManuscriptMarkup.respell!('Type 3', 'Type 4', [@path])

          assert_equal "Type 4 と Type 30 と Type 3D。\n", File.read(@path)
        end

        # 新しい綴りが古い綴りを含むとき、すでに新しい綴りで書いた箇所は二重にしない
        def test_respell_leaves_text_already_in_the_new_spelling
          File.write(@path, "Type 3 フォントと、Type 3 です。\n")

          count = ManuscriptMarkup.respell!('Type 3', 'Type 3 フォント', [@path])

          assert_equal 1, count
          assert_equal "Type 3 フォントと、Type 3 フォント です。\n", File.read(@path)
        end
      end
    end
  end
end
