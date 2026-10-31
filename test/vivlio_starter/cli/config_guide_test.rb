# frozen_string_literal: true

# ================================================================
# Test: config_guide_test.rb
# ================================================================
# テスト対象:
#   ConfigGuide（lib/vivlio_starter/cli/config_guide.rb）・vs config 系のコマンド
#
# 検証内容（config-command-spec.md）:
#   - book.yml の区分の一覧・キーの説明・言葉で探す
#   - catalog.yml・talk.yml の書き方と、その本の中身
#   - 今の値の 3 状態、1 行にまとめた子のキー、本の外
#   - 廃止キーと移したキーの案内、見つからないときの提案
#   - 実物の雛形で全キーを引けること
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'vivlio_starter/cli/samovar'

module VivlioStarter
  module CLI
    class ConfigGuideTest < Minitest::Test
      SCAFFOLD_BOOK = <<~YAML
        # =============================================================
        #  設定ガイド
        # =============================================================

        # ======= 書籍情報 =======
        book:
          # ------- 書籍名 -------
          main_title: "{{MAIN_TITLE}}"
          author: "{{AUTHOR}}" # 著者名

        # ======= 索引設定 =======
        index:
          target_terms: light # 索引語数の目安
                              #   light … 少なめ
                              #   260   … 語数を直接指定

          # 目次の語も候補にする倍率
          candidate_pool: 3.0

        # ======= 文章品質メトリクスの基準値 =======
        metrics:
          compact:
            section: { min: 400, max: 900 } # 節の文字数
      YAML

      SCAFFOLD_TALK = <<~YAML
        # ========================================
        # 会話文の設定
        # ========================================
        # 使わないなら、このファイルは削除して構いません。

        # ----------------------------------------
        # 表示設定
        # ----------------------------------------
        display:
          style: chat         # chat / inline
          avatar: on          # on / auto / off
          avatar_size: 12     # アバターの直径（mm）

        # 下の 2 人は記入例です。
        haruka:
          name: 遙香

        mirai:
          name: 未來

        # 95 章の話者
        einstein:
          name: アインシュタイン
      YAML

      SCAFFOLD_CATALOG = <<~YAML
        # ビルドする原稿を指定します
        # 例を使うときは、各行の先頭の「# 」を外してください。

        # 前書き
        PREFACE:
          - 00-preface

        # 本文
        CHAPTERS:
          - 13-pdf-read

        # 【基本形】
        # 本文が 1 章だけの例です。
        #
        # 【分冊にする】
        # 上下巻に分けます。
      YAML

      def setup
        @original_dir = Dir.pwd
        @work = Dir.mktmpdir('config_guide_test')
        @scaffold = File.join(@work, 'scaffold')
        @book = File.join(@work, 'book')
        FileUtils.mkdir_p(File.join(@scaffold, 'config'))
        FileUtils.mkdir_p(File.join(@book, 'config'))
        File.write(File.join(@scaffold, 'config/book.yml'), SCAFFOLD_BOOK)
        File.write(File.join(@scaffold, 'config/talk.yml'), SCAFFOLD_TALK)
        File.write(File.join(@scaffold, 'config/catalog.yml'), SCAFFOLD_CATALOG)
        Dir.chdir(@book)
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@work)
      end

      def show(query = nil, scaffold: @scaffold)
        status = nil
        out, err = capture_io { status = ConfigGuide::Book.new(scaffold_source: scaffold).show(query) }
        [status, out + err]
      end

      def show_talk(query = nil, scaffold: @scaffold)
        status = nil
        out, err = capture_io { status = ConfigGuide::Talk.new(scaffold_source: scaffold).show(query) }
        [status, out + err]
      end

      def show_catalog(scaffold: @scaffold)
        status = nil
        out, err = capture_io { status = ConfigGuide::Catalog.new(scaffold_source: scaffold).show }
        [status, out + err]
      end

      def write_book(text) = File.write('config/book.yml', text)

      # --- phase: 区分の一覧 ---

      def test_should_list_sections_with_their_names_and_the_ways_to_look_up
        status, out = show

        assert_equal 0, status
        assert_match(/^  book +書籍情報$/, out)
        assert_match(/^  index +索引設定$/, out)
        assert_match(/^  metrics +文章品質メトリクスの基準値$/, out)
        assert_includes out, 'vs config:book index.target_terms'
        refute_includes out, '設定ガイド', 'ファイルの頭の説明は区分の名前ではない'
      end

      # --- phase: キーの説明 ---

      def test_should_show_a_key_with_its_parent_and_scaffold_lines
        status, out = show('index.target_terms')

        assert_equal 0, status
        assert_includes out, "  # ======= 索引設定 =======\n  index:\n    target_terms: light # 索引語数の目安\n"
        assert_includes out, '#   260   … 語数を直接指定'
      end

      def test_should_show_the_comment_above_a_key
        _, out = show('index.candidate_pool')

        assert_includes out, "  index:\n    # 目次の語も候補にする倍率\n    candidate_pool: 3.0\n"
      end

      def test_should_show_a_section_with_its_children_and_without_a_value
        write_book("index:\n  target_terms: standard\n")

        status, out = show('index')

        assert_equal 0, status
        assert_includes out, 'target_terms: light'
        assert_includes out, 'candidate_pool: 3.0'
        refute_includes out, '今の値'
      end

      def test_should_not_show_the_placeholders_of_vs_new
        _, out = show('book.main_title')

        assert_includes out, 'main_title: ""'
        refute_includes out, '{{'
      end

      # 説明の無い子のキーは、親の説明を要約にする
      def test_should_borrow_the_summary_of_the_parent
        _, out = show('metrics.compact')

        assert_includes out, 'section: { min: 400'

        _, listing = show('metrics.')

        assert_match(/^  metrics\.compact\.section +節の文字数$/, listing)
        assert_match(/^  metrics\.compact +文章品質メトリクスの基準値$/, listing)
      end

      # --- phase: 今の値 ---

      def test_should_show_the_value_written_in_book_yml
        write_book("index:\n  target_terms: standard\n")

        _, out = show('index.target_terms')

        assert_includes out, '今の値: standard（config/book.yml）'
      end

      def test_should_show_the_default_when_the_key_is_not_written
        write_book("book:\n  author: 誰か\n")

        _, out = show('index.target_terms')

        assert_includes out, '今の値: 書いていません（既定値: light）'
      end

      # 著者が埋めるキーには既定値が無い
      def test_should_not_invent_a_default_for_an_authored_key
        write_book("index:\n  target_terms: light\n")

        _, out = show('book.author')

        assert_includes out, '今の値: 書いていません'
        refute_includes out, '既定値'
      end

      def test_should_show_an_empty_value_plainly
        write_book("book:\n  author: \"\"\n")

        _, out = show('book.author')

        assert_includes out, '今の値: （空）（config/book.yml）'
      end

      # `{ min: 400, max: 900 }` の min には自分の行が無いので、親の行を見せて値は min のものを出す
      def test_should_show_the_parent_line_for_a_key_inside_a_flow_mapping
        write_book("metrics:\n  compact:\n    section: { min: 500, max: 800 }\n")

        status, out = show('metrics.compact.section.min')

        assert_equal 0, status
        assert_includes out, 'section: { min: 400, max: 900 } # 節の文字数'
        assert_includes out, '今の値: 500（config/book.yml）'
      end

      def test_should_omit_the_value_outside_a_project
        FileUtils.rm_rf('config')

        status, out = show('index.target_terms')

        assert_equal 0, status
        assert_includes out, 'target_terms: light'
        refute_includes out, '今の値'
      end

      def test_should_omit_the_value_when_book_yml_cannot_be_read
        write_book("index: [\n")

        status, out = show('index.target_terms')

        assert_equal 0, status
        refute_includes out, '今の値'
      end

      def test_should_never_change_book_yml
        original = "index:\n  target_terms: standard # 著者のコメント\n"
        write_book(original)

        [nil, 'index', 'index.target_terms', '目次', 'nothing-like-this'].each { show(it) }

        assert_equal original, File.read('config/book.yml')
      end

      # --- phase: 言葉で探す ---

      def test_should_search_key_names_and_comments
        status, out = show('語数')

        assert_equal 0, status
        assert_includes out, 'target_terms: light', '1 件ならそのキーの説明を出す'
      end

      def test_should_list_every_match_with_a_summary
        status, out = show('index.')

        assert_equal 0, status
        assert_includes out, '「index.」を含む設定（2 件）'
        assert_match(/^  index\.target_terms +索引語数の目安$/, out)
        assert_match(/^  index\.candidate_pool +目次の語も候補にする倍率$/, out)
      end

      def test_should_ignore_case_when_searching
        _, out = show('TARGET_TERMS')

        assert_includes out, 'target_terms: light'
      end

      def test_should_look_at_the_words_below_a_key
        _, out = show('直接指定')

        assert_includes out, 'target_terms: light'
      end

      # --- phase: 廃止キー ---

      def test_should_explain_a_retired_key
        status, out = show('index.max_sub_references')

        assert_equal 0, status
        assert_includes out, 'index.max_sub_references は廃止されました'
        assert_includes out, '副次参照の最大値は 8 で固定になりました'
      end

      def test_should_point_a_moved_key_to_its_new_place
        status, out = show('output.cover')

        assert_equal 0, status
        assert_includes out, 'output.cover は book.cover へ移りました'
        assert_includes out, '→ vs config:book book.cover'
      end

      def test_should_explain_a_child_of_a_retired_section
        status, out = show('vivliostyle.image')

        assert_equal 0, status
        assert_includes out, 'vivliostyle は廃止されました'
      end

      # --- phase: 見つからないとき ---

      def test_should_suggest_the_nearest_key
        status, out = show('index.targt_terms')

        assert_equal 1, status
        assert_includes out, '「index.targt_terms」に当てはまる設定が見つかりませんでした'
        assert_includes out, '→ vs config:book index.target_terms'
      end

      def test_should_point_to_the_list_when_nothing_is_close
        status, out = show('まったく関係のない語')

        assert_equal 1, status
        assert_includes out, '→ vs config:book'
      end

      # --- phase: 実物の雛形 ---

      def test_every_section_of_the_real_scaffold_has_a_name
        status, out = show(nil, scaffold: NewCommands::SCAFFOLD_SOURCE)

        sections = out[/book\.yml の設定\n\n(.*?)\n\n/m, 1].lines

        assert_equal 0, status
        assert_equal 15, sections.size
        sections.each { assert_match(/\A  \S+ +\S/, it) }
      end

      def test_every_key_of_the_real_scaffold_can_be_shown
        scaffold = NewCommands::SCAFFOLD_SOURCE
        keys = ScaffoldLock.scaffold_book_keys(scaffold)

        keys.each do |key|
          status, out = show(key, scaffold:)

          assert_equal 0, status, key
          assert_includes out, key.split('.').last[0, 3], key
        end
      end

      def test_should_run_through_the_command
        write_book("index:\n  target_terms: standard\n")

        status = nil
        out, = capture_io { status = SamovarCommands::ConfigBookCommand.new(['index.target_terms']).call }

        assert_equal 0, status
        assert_includes out, '今の値: standard（config/book.yml）'
      end

      # 起動の時点で本を要求しないこと（直接呼ぶ上のテストでは確かめられない）
      def test_should_run_outside_a_project_from_the_command_line
        FileUtils.rm_rf('config')
        repo = File.expand_path('../../..', __dir__)

        out, status = Open3.capture2e(RbConfig.ruby, '-I', "#{repo}/lib", "#{repo}/bin/vs", 'config:book', 'index.target_terms')

        assert_predicate status, :success?, out
        assert_includes out, 'target_terms: light'
      end

      # --help を探す言葉として受け取らない
      def test_should_show_the_usage_for_help
        %w[--help -h].each do |flag|
          out, = capture_io { SamovarCommands::ConfigBookCommand.new([flag]).call }

          refute_includes out, '当てはまる設定が見つかりませんでした', flag
          assert_includes out, '区分・キー・探す言葉', flag
        end
      end

      def test_should_be_listed_in_the_help
        listed = SamovarCommands::HelpCommand::COMMAND_CATEGORIES.values.flatten

        %w[config config:book config:catalog config:talk].each { assert_includes listed, it }
      end

      # vs index と同じく、vs config は下位のコマンドの案内だけを出す
      def test_should_guide_to_the_three_commands
        status = nil
        out, = capture_io { status = SamovarCommands::ConfigCommand.new([]).call }

        assert_equal 0, status
        %w[vs\ config:book vs\ config:catalog vs\ config:talk].each { assert_includes out, it }
      end

      # --- phase: talk.yml ---

      def test_should_show_how_to_write_talk_yml_with_the_samples_only
        status, out = show_talk

        assert_equal 0, status
        assert_includes out, '# 使わないなら、このファイルは削除して構いません。'
        assert_includes out, 'style: chat'
        assert_includes out, 'mirai:'
        refute_includes out, 'einstein', '記入例の後の話者は本書のもの'
      end

      def test_should_list_the_speakers_of_this_book
        write_book("book:\n  author: 誰か\n")
        File.write('config/talk.yml', "display:\n  style: inline\nmary:\n  name: 真理\njohn: blue\n")

        _, out = show_talk

        assert_includes out, 'この本の話者（config/talk.yml）'
        assert_match(/^  mary +真理$/, out)
        assert_match(/^  john +john$/, out, '色だけの話者は表示名がキーになる')
        refute_match(/^  display/, out[/この本の話者.*/m])
      end

      def test_should_say_when_the_book_has_no_talk_yml
        write_book("book:\n  author: 誰か\n")

        _, out = show_talk

        assert_includes out, 'この本には config/talk.yml がありません'
      end

      def test_should_say_when_talk_yml_has_no_speakers
        write_book("book:\n  author: 誰か\n")
        File.write('config/talk.yml', "display:\n  style: inline\n")

        _, out = show_talk

        assert_includes out, 'config/talk.yml に話者が書かれていません'
      end

      def test_should_not_mention_speakers_outside_a_project
        _, out = show_talk

        refute_includes out, 'この本'
      end

      def test_should_show_a_display_key_with_its_value
        File.write('config/talk.yml', "display:\n  style: inline\n")

        status, out = show_talk('display.style')

        assert_equal 0, status
        assert_includes out, 'style: chat'
        assert_includes out, '今の値: inline（config/talk.yml）'
      end

      def test_should_show_the_default_of_a_display_key
        File.write('config/talk.yml', "haruka:\n  name: 遙香\n")

        _, out = show_talk('display.style')

        assert_includes out, '今の値: 書いていません（既定値: chat）'
      end

      # YAML は `avatar: on` を真偽値に読むので、書いた綴りへ戻す
      def test_should_spell_the_avatar_mode_as_written
        File.write('config/talk.yml', "display:\n  avatar: off\n")

        _, out = show_talk('display.avatar')

        assert_includes out, '今の値: off（config/talk.yml）'
      end

      # 話者は本ごとのものなので、キーとして引かない
      def test_should_not_look_up_the_sample_speakers
        status, out = show_talk('einstein')

        assert_equal 1, status
        assert_includes out, '→ vs config:talk'
      end

      def test_should_read_the_real_talk_yml
        status, out = show_talk(scaffold: NewCommands::SCAFFOLD_SOURCE)

        assert_equal 0, status
        assert_includes out, 'display:'
        refute_includes out, 'einstein:'

        status, out = show_talk('display.separator', scaffold: NewCommands::SCAFFOLD_SOURCE)

        assert_equal 0, status
        assert_includes out, 'separator:'
      end

      # --- phase: catalog.yml ---

      def test_should_show_how_to_write_catalog_yml_without_the_sample_chapters
        status, out = show_catalog

        assert_equal 0, status
        assert_includes out, '# ビルドする原稿を指定します'
        assert_includes out, '# 【分冊にする】'
        refute_includes out, '13-pdf-read', '雛形の値は本書の章立て'
        refute_includes out, '# 前書き', '値の見出しは説明ではない'
      end

      def test_should_show_the_structure_of_this_book
        File.write('config/catalog.yml', "# 著者のコメント\nPREFACE:\n  - 00-preface\nCHAPTERS:\n  - 第一部:\n      - 11-mine\n")

        _, out = show_catalog

        assert_includes out, 'この本の章立て（config/catalog.yml）'
        assert_includes out, "  CHAPTERS:\n    - 第一部:\n        - 11-mine\n"
        refute_includes out, '著者のコメント'
      end

      def test_should_not_show_a_structure_outside_a_project
        _, out = show_catalog

        refute_includes out, 'この本の章立て'
      end

      def test_should_read_the_real_catalog_yml
        status, out = show_catalog(scaffold: NewCommands::SCAFFOLD_SOURCE)

        assert_equal 0, status
        assert_includes out, '# 【分冊にする】'
        refute_includes out, '- 13-pdf-read'
      end

      def test_should_never_change_catalog_yml_or_talk_yml
        catalog = "CHAPTERS:\n  - 11-mine # 著者のコメント\n"
        talk = "display:\n  style: inline # 著者のコメント\n"
        File.write('config/catalog.yml', catalog)
        File.write('config/talk.yml', talk)

        show_catalog
        [nil, 'display.style', 'nothing-like-this'].each { show_talk(it) }

        assert_equal catalog, File.read('config/catalog.yml')
        assert_equal talk, File.read('config/talk.yml')
      end
    end
  end
end
