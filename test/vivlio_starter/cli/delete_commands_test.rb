# frozen_string_literal: true

# ================================================================
# Test: delete_commands_test.rb
# ================================================================
# テスト対象:
#   DeleteCommands モジュール（lib/vivlio_starter/cli/delete.rb）
#
# 検証内容:
#   - 確認に「はい」と答えた章 Markdown と画像ディレクトリの削除
#   - 確認に「いいえ」と答えた章は、目次・辞書も含めて何も変えない
#   - 原稿の無い目次の項目も、確認してから外す
#   - 端末でないときは何も消さずに止まる
#   - 対象が見つからない場合の終了コード 1
#
# テスト環境:
#   - 一時ディレクトリで副作用を隔離
#   - catalog.yml を自動生成（CatalogUpdater が必要とする）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'yaml'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/delete'

module VivlioStarter
  module CLI
    # DeleteCommands のユニットテスト
    class DeleteCommandsTest < Minitest::Test
      # 確認に「はい」と答えると章 Markdown と画像ディレクトリが削除されることを確認
      def test_delete_removes_markdown_and_images_when_confirmed
        within_temp_dir do
          setup_chapter_fixture('11-sample')

          with_stdin("y\ny\n") { run_delete(['11-sample']) }

          refute File.exist?(File.join(Common::CONTENTS_DIR, '11-sample.md')), '章 Markdown が削除されるはずです'
          refute Dir.exist?(File.join(Common::IMAGES_DIR, '11-sample')), '画像ディレクトリが削除されるはずです'
        end
      end

      def test_delete_accepts_slug_only_target
        within_temp_dir do
          setup_chapter_fixture('11-sample')

          with_stdin("y\ny\n") { run_delete(['sample']) }

          refute File.exist?(File.join(Common::CONTENTS_DIR, '11-sample.md'))
          refute Dir.exist?(File.join(Common::IMAGES_DIR, '11-sample'))
        end
      end

      def test_delete_handles_numeric_only_chapter
        within_temp_dir do
          setup_chapter_fixture('15')

          with_stdin("y\ny\n") { run_delete(['15']) }

          refute File.exist?(File.join(Common::CONTENTS_DIR, '15.md'))
          refute Dir.exist?(File.join(Common::IMAGES_DIR, '15'))
        end
      end

      # 消した章を指す索引辞書の main: を外す（vs rename の追随と対・改善案.md #108）
      def test_delete_forgets_main_references_to_the_deleted_chapter
        within_temp_dir do
          setup_chapter_fixture('11-sample')
          File.write('config/index_glossary_terms.yml', {
            'terms' => [
              { 'term' => 'テスト', 'yomi' => 'てすと', 'flags' => 'i', 'main' => ['11-sample'] },
              { 'term' => 'CSS', 'yomi' => 'CSS', 'flags' => 'i', 'main' => %w[11-sample 15] }
            ]
          }.to_yaml)

          with_stdin("y\ny\n") { run_delete(['11-sample']) }

          terms = YAML.load_file('config/index_glossary_terms.yml')['terms'].to_h { [it['term'], it] }
          refute terms['テスト'].key?('main'), '空になった語は「未決定」に戻す'
          assert_equal ['15'], terms['CSS']['main']
        end
      end

      # 確認に「いいえ」と答えた章は、目次にも辞書にも手を付けない（本から黙って消えないように）
      def test_delete_keeps_everything_when_the_answer_is_no
        within_temp_dir do
          setup_chapter_fixture('11-sample')
          dictionary = { 'terms' => [{ 'term' => 'テスト', 'yomi' => 'てすと', 'flags' => 'i', 'main' => ['11-sample'] }] }.to_yaml
          File.write('config/index_glossary_terms.yml', dictionary)
          catalog = File.read('config/catalog.yml')

          summary = with_stdin("n\nn\n") { run_delete(['11-sample']) }

          assert_path_exists File.join(Common::CONTENTS_DIR, '11-sample.md')
          assert_path_exists File.join(Common::IMAGES_DIR, '11-sample')
          assert_equal catalog, File.read('config/catalog.yml')
          assert_equal dictionary, File.read('config/index_glossary_terms.yml')
          assert_predicate summary, :none?
        end
      end

      # 答えずに入力を閉じた（Ctrl-D）ときも「いいえ」と同じ
      def test_delete_keeps_the_catalog_when_stdin_is_closed
        within_temp_dir do
          setup_chapter_fixture('11-sample')
          catalog = File.read('config/catalog.yml')

          summary = with_stdin('') { run_delete(['11-sample']) }

          assert_equal catalog, File.read('config/catalog.yml')
          assert_predicate summary, :none?
        end
      end

      # 引数なしは全章に確認する。全部「いいえ」なら目次は 1 行も減らない
      def test_delete_without_targets_keeps_the_catalog_when_every_answer_is_no
        within_temp_dir do
          setup_chapter_fixture('11-sample')
          setup_chapter_fixture('15')
          catalog = File.read('config/catalog.yml')

          summary = with_stdin("n\n" * 4) { run_delete([]) }

          assert_equal catalog, File.read('config/catalog.yml')
          assert_predicate summary, :none?
        end
      end

      # 原稿を消すと答えたら、画像を残しても目次からは外す（原稿の無い章が目次に残らないように）
      def test_delete_removes_the_catalog_entry_with_the_document
        within_temp_dir do
          setup_chapter_fixture('11-sample')

          summary = with_stdin("y\nn\n") { run_delete(['11-sample']) }

          refute_path_exists File.join(Common::CONTENTS_DIR, '11-sample.md')
          assert_path_exists File.join(Common::IMAGES_DIR, '11-sample')
          assert_equal %w[15], catalog_items
          assert_equal [1, 0, 0], [summary.documents, summary.image_dirs, summary.catalog_entries]
        end
      end

      # 画像だけ消すと答えた章は原稿が残るので、目次からは外さない
      def test_delete_keeps_the_catalog_entry_when_only_images_are_deleted
        within_temp_dir do
          setup_chapter_fixture('11-sample')

          summary = with_stdin("n\ny\n") { run_delete(['11-sample']) }

          assert_path_exists File.join(Common::CONTENTS_DIR, '11-sample.md')
          refute_path_exists File.join(Common::IMAGES_DIR, '11-sample')
          assert_equal %w[11-sample 15], catalog_items
          assert_equal [0, 1, 0], [summary.documents, summary.image_dirs, summary.catalog_entries]
        end
      end

      # 原稿の無い章は目次の項目だけが消す対象。これも確認してから外す
      def test_delete_asks_before_removing_an_entry_without_a_document
        within_temp_dir do
          out, summary = with_stdin("n\n") { run_delete_with_output(['11-sample']) }

          assert_includes out, '目次の項目: config/catalog.yml の 11-sample'
          assert_equal %w[11-sample 15], catalog_items
          assert_predicate summary, :none?

          summary = with_stdin("y\n") { run_delete(['11-sample']) }

          assert_equal %w[15], catalog_items
          assert_equal 1, summary.catalog_entries
          refute_predicate summary, :none?
        end
      end

      def test_delete_removes_entries_with_and_without_a_document
        within_temp_dir do
          setup_chapter_fixture('11-sample')
          File.write('config/catalog.yml', "CHAPTERS:\n  - 11-sample\n  - 16-planned\n")

          summary = with_stdin("y\n" * 3) { run_delete(%w[11-sample 16-planned]) }

          assert_empty catalog_items
          assert_equal [1, 1, 1], [summary.documents, summary.image_dirs, summary.catalog_entries]
        end
      end

      # 消した原稿は戻せないので、答えは端末からだけ受ける。章の指定を忘れた `yes | vs delete` も通さない
      def test_delete_stops_without_a_terminal
        within_temp_dir do
          setup_chapter_fixture('11-sample')
          catalog = File.read('config/catalog.yml')

          [['11-sample'], []].each do |tokens|
            error = nil
            out, err = with_stdin("y\n" * 4, terminal: false) do
              capture_io { error = assert_raises(SystemExit) { DeleteCommands::DeleteCommandExecutor.new({}, tokens).call } }
            end

            assert_equal 1, error.status
            assert_includes out + err, '端末から vs delete を実行してください'
            assert_path_exists File.join(Common::CONTENTS_DIR, '11-sample.md')
            assert_path_exists File.join(Common::IMAGES_DIR, '11-sample')
            assert_equal catalog, File.read('config/catalog.yml')
          end
        end
      end

      # 対象が見つからない場合に終了コード 1 で終了することを確認
      def test_delete_exits_when_targets_missing
        within_temp_dir do
          error = assert_raises(SystemExit) do
            capture_io { DeleteCommands::DeleteCommandExecutor.new({}, ['11-missing']).call }
          end
          assert_equal 1, error.status
        end
      end

      private

      def run_delete(tokens) = run_delete_with_output(tokens).last

      def run_delete_with_output(tokens)
        summary = nil
        out, = capture_io { summary = DeleteCommands::DeleteCommandExecutor.new({}, tokens).call }
        [out, summary]
      end

      # catalog.yml の CHAPTERS の項目
      def catalog_items = Array(YAML.load_file('config/catalog.yml')['CHAPTERS']).map(&:to_s)

      # 確認プロンプトへの答えを流し込む。terminal: false はパイプからの入力
      def with_stdin(input, terminal: true)
        original = $stdin
        $stdin = StringIO.new(input)
        $stdin.define_singleton_method(:tty?) { terminal }
        yield
      ensure
        $stdin = original
      end

      # 章の Markdown と画像ディレクトリを用意
      def setup_chapter_fixture(slug)
        FileUtils.mkdir_p(Common::CONTENTS_DIR)
        FileUtils.mkdir_p(Common::IMAGES_DIR)
        File.write(File.join(Common::CONTENTS_DIR, "#{slug}.md"), "# #{slug}\n")
        FileUtils.mkdir_p(File.join(Common::IMAGES_DIR, slug))
      end

      # 一時ディレクトリを利用して副作用を隔離
      def within_temp_dir
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p(Common::CONTENTS_DIR)
            FileUtils.mkdir_p(Common::IMAGES_DIR)
            FileUtils.mkdir_p('config')
            # catalog.yml を作成（CatalogUpdater が必要とする）
            File.write('config/catalog.yml', <<~YAML)
              PREFACE:
              CHAPTERS:
                - 11-sample
                - 15
              APPENDICES:
              POSTFACE:
            YAML
            yield dir
          end
        end
      end
    end
  end
end
