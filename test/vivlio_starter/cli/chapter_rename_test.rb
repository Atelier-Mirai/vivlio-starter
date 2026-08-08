# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/chapter_rename'
require 'vivlio_starter/cli/rename'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    # 章名の変更に追随すべき処理の登録簿（chapter-rename-followers-spec.md）
    #
    # 起票の経緯: vs rename / vs renumber は原稿ファイル・catalog.yml・画像
    # ディレクトリしか更新せず、索引辞書の main: が黙って壊れていた。追随先が
    # 増えるたびに 2 つの実行経路へ直書きするのをやめ、登録簿へ集約した。
    class ChapterRenameTest < Minitest::Test
      OLD = '21-markdown-tutorial'
      NEW = '20-markdown-tutorial'

      def setup
        @original_dir = Dir.pwd
        @temp_dir = Dir.mktmpdir('chapter_rename_test')
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p(%w[contents config images])
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
      end

      def write_dictionary(terms:, scanned: nil)
        data = { 'terms' => terms }
        data['scanned_chapters'] = scanned if scanned
        File.write('config/index_glossary_terms.yml', data.to_yaml)
      end

      def dictionary = YAML.load_file('config/index_glossary_terms.yml')

      def term(name, main: nil)
        entry = { 'term' => name, 'yomi' => name, 'flags' => 'i' }
        entry['main'] = main if main
        entry
      end

      # rename.rb と同じ順序（ファイル移動 → 追随）を再現する
      def rename_with_file_move
        File.write("contents/#{NEW}.md", "# 章\n")
        ChapterRename.follow!(OLD, NEW)
      end

      # --- phase: 索引辞書の追随（R1・R2） ---

      # main: は著者の判断＝一次データなので、実在しない章を指していても捨てられない。
      # contexts のように「捨てて拾い直す」ことができないため書き換える。
      def test_main_reference_follows_the_rename
        write_dictionary(terms: [term('Markdown', main: [OLD, '22-extentions'])])

        rename_with_file_move

        assert_equal [NEW, '22-extentions'], dictionary['terms'].first['main']
      end

      # 著者が書いた形を保つ（単一指定を配列にしない）
      def test_single_main_stays_single
        write_dictionary(terms: [term('Markdown', main: OLD)])

        rename_with_file_move

        assert_equal NEW, dictionary['terms'].first['main']
      end

      def test_unrelated_terms_are_untouched
        write_dictionary(terms: [term('無関係'), term('別の章', main: '33-index-glossary')])

        rename_with_file_move

        assert_nil dictionary['terms'].find { it['term'] == '無関係' }['main']
        assert_equal '33-index-glossary', dictionary['terms'].find { it['term'] == '別の章' }['main']
      end

      def test_scanned_chapters_follow_the_rename
        write_dictionary(terms: [term('Markdown')], scanned: [OLD])

        rename_with_file_move

        assert_equal [NEW], dictionary['scanned_chapters']
      end

      # --- phase: 既存の追随先（R3・挙動不変） ---

      def test_catalog_follows_the_rename
        File.write('config/catalog.yml', { 'chapters' => [OLD] }.to_yaml)
        write_dictionary(terms: [])

        rename_with_file_move

        assert_equal [NEW], YAML.load_file('config/catalog.yml')['chapters']
      end

      def test_image_directory_follows_the_rename
        FileUtils.mkdir_p("images/#{OLD}")
        File.write("images/#{OLD}/fig.png", 'x')
        write_dictionary(terms: [])

        rename_with_file_move

        assert_path_exists "images/#{NEW}/fig.png"
        refute_path_exists "images/#{OLD}"
      end

      # 移動先が既にあるときは統合の判断が要るので、上書きせず著者へ委ねる
      def test_image_directory_conflict_warns_instead_of_overwriting
        FileUtils.mkdir_p(["images/#{OLD}", "images/#{NEW}"])
        File.write("images/#{OLD}/old.png", 'old')
        File.write("images/#{NEW}/new.png", 'new')
        write_dictionary(terms: [])

        out, err = capture_io { rename_with_file_move }

        assert_match(/手動で統合/, out + err)
        assert_path_exists "images/#{OLD}/old.png", '上書きしない'
        assert_path_exists "images/#{NEW}/new.png"
      end

      # --- phase: 失敗しても止めない（§2.1） ---

      # 原稿ファイルの移動は追随より先に済んでいる。途中で止めると
      # 「ファイルは新しい名前、catalog は古い名前」という中途半端な状態が残る。
      def test_one_failing_follower_does_not_stop_the_others
        reached = []
        followers = [
          ChapterRename::Follower.new(label: '壊れる追随先', handler: ->(*) { raise 'boom' }),
          ChapterRename::Follower.new(label: '後続', handler: ->(*) { reached << :after })
        ]

        out, err = capture_io { ChapterRename.follow!(OLD, NEW, followers:) }

        assert_equal [:after], reached, '前の追随先が落ちても後続は実行される'
        assert_match(/壊れる追随先/, out + err, '失敗した追随先を名指しで知らせる')
        assert_match(/手作業/, out + err, '復旧の手がかりを添える')
      end

      def test_follow_never_raises
        followers = [ChapterRename::Follower.new(label: 'x', handler: ->(*) { raise 'boom' })]

        capture_io { ChapterRename.follow!(OLD, NEW, followers:) }
      end

      # 実際の追随先どうしでも、1 つが空振りしても他は進む
      def test_missing_catalog_does_not_block_dictionary_update
        write_dictionary(terms: [term('Markdown', main: OLD)])

        capture_io { rename_with_file_move }

        assert_equal NEW, dictionary['terms'].first['main'],
                     'catalog.yml が無くても辞書は追随する'
      end

      # --- phase: 登録簿の健全性 ---

      # 追随先を足すときに label を書き忘れると、失敗しても何が落ちたか分からない
      def test_every_follower_has_a_label_and_handler
        ChapterRename::FOLLOWERS.each do |follower|
          refute_empty follower.label.to_s.strip
          assert_respond_to follower.handler, :call
        end
      end

      def test_registry_covers_the_known_followers
        labels = ChapterRename::FOLLOWERS.map(&:label)

        assert_includes labels, 'catalog.yml'
        assert_includes labels, '画像ディレクトリ'
        assert_includes labels, '索引辞書'
      end
    end
  end
end
