# frozen_string_literal: true

# ================================================================
# Test: clean_commands_test.rb
# ================================================================
# テスト対象:
#   CleanCommands モジュール（lib/vivlio_starter/cli/clean.rb）
#
# 検証内容:
#   - --purge なし: ワークスペースのみ削除、最終 PDF は保持
#   - --purge あり: 最終 PDF も含めてすべて削除
#   - --cache: キャッシュディレクトリのみ削除
#   - --cover: 生成キャッシュのみ削除（covers/ の著者ソースは触れない）
#   - **ルートを掃かないこと**——中間生成物は .cache/vs/build/ に閉じており、
#     著者が置いた *.html / NN-*.md / images/ の下位 dir は消えてはならない
#     （2026-09-12 に legacy 掃除を撤去。以前はこれらを毎ビルド薙いでいた）
#
# テスト環境:
#   - 一時ディレクトリで副作用を隔離
#   - 必須設定ファイルを自動生成
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/clean'

module VivlioStarter
  module CLI
    # CleanCommands のユニットテスト
    class CleanCommandsTest < Minitest::Test
      # --purge なしで中間生成物のみ削除され最終 PDF が残ることを確認
      def test_clean_preserves_final_pdfs_without_purge
        within_temp_dir do
          setup_generated_files
          CleanCommands.execute_clean({})

          assert_clean_directory
          assert_final_pdfs_exist
          assert File.exist?('11-sample.pdf'), '単章PDFは purge なしでは残るはずです'
        end
      end

      # --purge 指定で clean 実行時、最終PDFや単章PDFも削除されることを確認
      def test_clean_with_purge_removes_final_outputs
        within_temp_dir do
          setup_generated_files
          CleanCommands.execute_clean({ purge: true })

          assert_clean_directory
          assert_final_pdfs_removed
          refute File.exist?('11-sample.pdf'), 'purge 指定時は単章PDFも削除されるはずです'
        end
      end

      # 索引レビューファイルは著者が編集する入力なので、既定の掃除では残す。
      # ビルドのたびに消えると、レビュー途中の判断がまるごと失われる。
      def test_clean_preserves_the_index_review_file
        within_temp_dir do
          setup_generated_files
          write_file('_index_glossary_review.md')

          CleanCommands.execute_clean({})

          assert File.exist?('_index_glossary_review.md'), 'レビュー途中の編集を消してはいけません'
        end
      end

      # 掃除の意図が明示された --purge のときだけ消す
      def test_purge_removes_the_index_review_file
        within_temp_dir do
          setup_generated_files
          write_file('_index_glossary_review.md')

          CleanCommands.execute_clean({ purge: true })

          refute File.exist?('_index_glossary_review.md')
        end
      end

      # --cache 指定で clean 実行時、キャッシュのみ削除されることを確認
      def test_clean_cache_only_removes_cache_directory
        within_temp_dir do
          setup_generated_files
          cache_dir = VivlioStarter::CLI::Common.cache_dir
          FileUtils.mkdir_p(cache_dir)
          write_file(File.join(cache_dir, 'cached.pdf'))

          CleanCommands.execute_clean({ cache: true })

          refute Dir.exist?(cache_dir), 'キャッシュディレクトリは削除されるべきです'
          assert_author_files_intact
          assert_final_pdfs_exist
          assert File.exist?('11-sample.pdf'), '単章PDFは保持されるはずです'
        end
      end

      # --cover 指定で clean 実行時、カバー画像のみ削除されることを確認
      def test_clean_cover_only_removes_cover_files
        within_temp_dir do
          setup_generated_files
          setup_cover_files
          setup_config_for_cover

          CleanCommands.execute_clean({ cover: true })

          # カバー画像が削除されること
          assert_cover_files_removed
          # マスター画像は保持されること
          assert_master_files_exist
          # 通常の生成物は保持されること
          assert Dir.exist?(VivlioStarter::CLI::Common::BUILD_DIR),
                 '--cover ではワークスペースを削除しないはずです'
          assert_author_files_intact
          assert_final_pdfs_exist
        end
      end

      # ビルドの Step 0 が呼ぶ形（オプションなし）。ワークスペースだけを消し、
      # 著者がルートや images/ に置いたものには一切触れない。
      def test_default_clean_never_touches_author_files
        within_temp_dir do
          setup_generated_files
          write_file(File.join('contents', '11-sample.md'))

          CleanCommands.execute_clean({})

          assert_author_files_intact
          assert File.exist?(File.join('contents', '11-sample.md')), '原稿を消してはいけません'
        end
      end

      # --cover --cache 指定で clean 実行時、カバー画像とキャッシュが削除されることを確認
      def test_clean_cover_and_cache
        within_temp_dir do
          setup_generated_files
          setup_cover_files
          setup_config_for_cover
          cache_dir = VivlioStarter::CLI::Common.cache_dir
          FileUtils.mkdir_p(cache_dir)
          write_file(File.join(cache_dir, 'cached.pdf'))

          CleanCommands.execute_clean({ cover: true, cache: true })

          # カバー画像が削除されること
          assert_cover_files_removed
          # キャッシュが削除されること
          refute Dir.exist?(cache_dir), 'キャッシュディレクトリは削除されるべきです'
          # 通常の生成物は保持されること
          assert_author_files_intact
          assert_final_pdfs_exist
        end
      end

      # --cover --purge 指定で clean 実行時、カバー画像と通常のクリーンが実行されることを確認
      def test_clean_cover_and_purge
        within_temp_dir do
          setup_generated_files
          setup_cover_files
          setup_config_for_cover

          CleanCommands.execute_clean({ cover: true, purge: true })

          # カバー画像が削除されること
          assert_cover_files_removed
          # 通常のクリーンも実行されること
          assert_clean_directory
          assert_final_pdfs_removed
        end
      end

      # --cover --cache --purge 指定で clean 実行時、すべてが削除されることを確認
      def test_clean_cover_cache_and_purge
        within_temp_dir do
          setup_generated_files
          setup_cover_files
          setup_config_for_cover
          cache_dir = VivlioStarter::CLI::Common.cache_dir
          FileUtils.mkdir_p(cache_dir)
          write_file(File.join(cache_dir, 'cached.pdf'))

          CleanCommands.execute_clean({ cover: true, cache: true, purge: true })

          # カバー画像が削除されること
          assert_cover_files_removed
          # キャッシュが削除されること
          refute Dir.exist?(cache_dir), 'キャッシュディレクトリは削除されるべきです'
          # 通常のクリーンも実行されること
          assert_clean_directory
          assert_final_pdfs_removed
        end
      end

      # --all 指定で clean 実行時、開発者用のフルクリーンが行われることを確認
      def test_clean_with_all_option
        within_temp_dir do
          setup_generated_files
          setup_cover_files
          setup_config_for_cover
          cache_dir = VivlioStarter::CLI::Common.cache_dir
          FileUtils.mkdir_p(cache_dir)
          write_file(File.join(cache_dir, 'cached.pdf'))

          CleanCommands.execute_clean({ all: true })

          # カバー画像が削除されること
          assert_cover_files_removed
          # キャッシュが削除されること
          refute Dir.exist?(cache_dir), '--all ではキャッシュを削除するはずです'
          # 通常のクリーンも実行されること
          assert_clean_directory
          assert_final_pdfs_removed
        end
      end

      # --index-dictionaries で 3 つの辞書（terms/rejected/読みの個人辞書）が削除されることを確認
      def test_clean_index_dictionaries_removes_yomi_overrides
        within_temp_dir do
          FileUtils.mkdir_p('config')
          %w[index_glossary_terms.yml index_glossary_rejected.yml index_yomi_overrides.yml].each do |name|
            write_file(File.join('config', name))
          end

          with_stdin("y\n") do
            capture_io { CleanCommands.execute_clean({ index_dictionaries: true }) }
          end

          refute File.exist?('config/index_glossary_terms.yml'), '登録済み用語辞書は削除されるべきです'
          refute File.exist?('config/index_glossary_rejected.yml'), '除外用語辞書は削除されるべきです'
          refute File.exist?('config/index_yomi_overrides.yml'), '読みの個人辞書は削除されるべきです'
        end
      end

      # covers/ は著者ソース専用。ファイル名も拡張子も問わず --cover で消えない。
      # 生成物の正位置は .cache/vs/covers/ で、そちらだけが掃除の対象になる。
      def test_clean_cover_never_touches_the_covers_directory
        within_temp_dir do
          setup_generated_files
          covers_dir = 'covers'
          %w[custom_front.pdf custom_back.pdf custom_cover.jpg frontcover_master.png].each do |name|
            write_file(File.join(covers_dir, name))
          end
          setup_custom_config_for_cover('custom_front.pdf', 'custom_back.pdf', 'custom_cover.jpg')

          CleanCommands.execute_clean({ cover: true })

          %w[custom_front.pdf custom_back.pdf custom_cover.jpg frontcover_master.png].each do |name|
            assert File.exist?(File.join(covers_dir, name)),
                   "covers/#{name} は著者ソースなので保持されるべきです"
          end
        end
      end

      private

      # 一時ディレクトリ配下でテストを実行する
      def within_temp_dir
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) { yield dir }
        end
      end

      # clean 対象となる生成物一式を用意する。中間物はワークスペース内、
      # ルートに出るのは最終成果物と単章 PDF だけ——これが P4 以降の実態。
      def setup_generated_files
        build_dir = VivlioStarter::CLI::Common::BUILD_DIR
        write_file(File.join(build_dir, 'html', '11-sample.html'))
        write_file(File.join(build_dir, 'pdf', '_titlepage.pdf'))
        write_file(File.join(build_dir, 'html', '_toc.md'))

        write_file('11-sample.pdf')
        pdf_output_files.each { |path| write_file(path) }

        setup_author_owned_files
      end

      # 著者の持ち物。clean はどのオプションでもこれらに触れてはならない。
      # ルートの *.html と NN-*.md、images/ の下位 dir は、かつて legacy 掃除が
      # 毎ビルド薙いでいた場所そのものである。
      def setup_author_owned_files
        write_file('notes.html')
        write_file('01-memo.md')
        write_file('book-settings.css')
        write_file(File.join('images', 'headings', 'author_drawn.webp'))
        write_file(File.join('images', 'math', 'author_formula.svg'))
      end

      # 中間生成物が削除されたことを検証する
      def assert_clean_directory
        refute Dir.exist?(VivlioStarter::CLI::Common::BUILD_DIR),
               'ビルドワークスペースは削除されるべきです'
        assert_author_files_intact
      end

      # 著者の持ち物が残っていることを検証する
      def assert_author_files_intact
        %w[notes.html 01-memo.md book-settings.css].each do |name|
          assert File.exist?(name), "著者がルートに置いた #{name} を消してはいけません"
        end
        assert File.exist?(File.join('images', 'headings', 'author_drawn.webp')),
               '著者の images/headings/ を消してはいけません'
        assert File.exist?(File.join('images', 'math', 'author_formula.svg')),
               '著者の images/math/ を消してはいけません'
      end

      # 最終出力PDFが残っていることを検証する
      def assert_final_pdfs_exist
        pdf_output_files.each do |path|
          assert File.exist?(path), "#{path} は保持されるべきです"
        end
      end

      # 最終出力PDFが削除されたことを検証する
      def assert_final_pdfs_removed
        pdf_output_files.each do |path|
          refute File.exist?(path), "#{path} は purge 指定時に削除されるべきです"
        end
      end

      # 最終PDF名（vivliostyle build の既定出力とその圧縮版。
      # レガシー pdf: セクションによる上書きは Phase 2 で廃止済み）
      def pdf_output_files
        %w[output.pdf output_compressed.pdf]
      end

      # 確認プロンプト用に $stdin を差し替える
      def with_stdin(input)
        original = $stdin
        $stdin = StringIO.new(input)
        yield
      ensure
        $stdin = original
      end

      # テスト用に空ファイルを生成する
      def write_file(path)
        FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == '.'
        FileUtils.touch(path)
      end

      # カバーの生成物は生成キャッシュ（.cache/vs/covers/）に出る。covers/ は
      # 著者ソース専用で、拡張子を問わず clean の対象外。
      def setup_cover_files
        cache_dir = VivlioStarter::CLI::Common.cover_cache_dir
        %w[frontcover_rgb.pdf backcover_rgb.pdf frontcover_cmyk.pdf
           frontcover_light.svg cover.jpg].each do |name|
          write_file(File.join(cache_dir, name))
        end

        covers_dir = 'covers'
        # 著者ソース。png/svg だけでなく pdf/jpg を置いても消えてはならない
        # （かつての legacy 掃除は covers/*.pdf と *.jpg を無条件に消していた）。
        %w[frontcover_master.png backcover_master.png
           frontcover_hand_drawn.pdf backcover_photo.jpg].each do |name|
          write_file(File.join(covers_dir, name))
        end
      end

      # カバー画像用の設定ファイルを生成
      def setup_config_for_cover
        FileUtils.mkdir_p('config')
        config = {
          'directories' => {
            'covers' => 'covers'
          },
          'output' => {
            'cover' => 'master',
            'targets' => 'pdf'
          }
        }
        File.write('config/book.yml', config.to_yaml)
      end

      # カスタムファイル名の設定ファイルを生成
      def setup_custom_config_for_cover(_front_pdf, _back_pdf, _epub_cover)
        FileUtils.mkdir_p('config')
        config = {
          'directories' => {
            'covers' => 'covers'
          },
          'output' => {
            'cover' => 'master',
            'targets' => 'pdf'
          }
        }
        File.write('config/book.yml', config.to_yaml)
      end

      # 生成キャッシュが丸ごと消えたことを検証する
      def assert_cover_files_removed
        refute Dir.exist?(VivlioStarter::CLI::Common.cover_cache_dir),
               'カバー生成キャッシュは削除されるべきです'
      end

      # covers/ の著者ソースが 1 つも消えていないことを検証する
      def assert_master_files_exist
        covers_dir = 'covers'
        %w[frontcover_master.png backcover_master.png
           frontcover_hand_drawn.pdf backcover_photo.jpg].each do |name|
          assert File.exist?(File.join(covers_dir, name)),
                 "covers/#{name} は著者ソースなので保持されるべきです"
        end
      end
    end
  end
end
