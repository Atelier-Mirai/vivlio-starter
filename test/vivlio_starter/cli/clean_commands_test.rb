# frozen_string_literal: true

# ================================================================
# Test: clean_commands_test.rb
# ================================================================
# テスト対象:
#   CleanCommands モジュール（lib/vivlio_starter/cli/clean.rb）
#
# 検証内容:
#   - オプションなし: .cache/ を丸ごと削除し、ルート直下の生成物は残す
#   - --purge: キャッシュに加えてルート直下の生成物も削除
#   - --index-dictionaries: 辞書だけを削除（キャッシュには触れない）
#   - clean_build_workspace: ビルドの作業フォルダだけを削除し、キャッシュは残す
#   - .vs-backup/ と covers/ には、どのオプションでも触れない
#   - **ルートを掃かないこと**——著者が置いた *.html / NN-*.md / images/ の下位 dir は
#     消えてはならない（2026-09-12 に legacy 掃除を撤去。以前はこれらを毎ビルド薙いでいた）
#
# テスト環境:
#   - 一時ディレクトリで副作用を隔離
#   - 必須設定ファイルを自動生成
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/clean'

module VivlioStarter
  module CLI
    # CleanCommands のユニットテスト
    class CleanCommandsTest < Minitest::Test
      # オプションなしは .cache/ を丸ごと削除する。ビルドの作業フォルダも、
      # 表紙・扉絵の生成画像も、.cache/vs/ の外のキャッシュ（metrics など）もこの下にある
      def test_should_remove_the_whole_cache_directory_by_default
        within_temp_dir do
          setup_generated_files
          setup_cache_files

          summary = CleanCommands.execute_clean({})

          refute Dir.exist?('.cache'), '.cache/ は丸ごと削除されるべきです'
          assert_equal 2, summary.cache, '.cache/ 直下の vs・metrics の 2 件を数えるべきです'
          assert_equal 0, summary.artifacts
          assert_author_files_intact
          assert_final_pdfs_exist
          assert File.exist?('11-sample.pdf'), '単章PDFは purge なしでは残るはずです'
        end
      end

      # 索引レビューファイルは著者が編集する入力なので、既定の掃除では残す。
      def test_should_keep_the_index_review_file_by_default
        within_temp_dir do
          setup_generated_files
          write_file('_index_glossary_review.md')

          CleanCommands.execute_clean({})

          assert File.exist?('_index_glossary_review.md'), 'レビュー途中の編集を消してはいけません'
        end
      end

      # --purge はキャッシュに加えて、ルート直下の生成物（単章 PDF・レビューファイルも）を削除する
      def test_should_remove_cache_and_root_artifacts_with_purge
        within_temp_dir do
          setup_generated_files
          setup_cache_files
          write_file('_index_glossary_review.md')

          summary = CleanCommands.execute_clean({ purge: true })

          refute Dir.exist?('.cache'), '--purge でもキャッシュは削除されるべきです'
          assert_final_pdfs_removed
          refute File.exist?('11-sample.pdf'), 'purge 指定時は単章PDFも削除されるはずです'
          refute File.exist?('_index_glossary_review.md')
          assert_operator summary.artifacts, :>=, 4
          assert_author_files_intact
        end
      end

      # vs upgrade の退避（.vs-backup/）と covers/ の著者ソースは、--purge でも残す
      def test_should_never_touch_backups_or_cover_sources
        within_temp_dir do
          setup_generated_files
          setup_cache_files
          write_file(File.join('.vs-backup', 'upgrade', '20261106-120000', 'config', 'book.yml'))
          %w[frontcover_master.png backcover_photo.jpg frontcover_hand_drawn.pdf].each do |name|
            write_file(File.join('covers', name))
          end

          CleanCommands.execute_clean({ purge: true })

          assert File.exist?(File.join('.vs-backup', 'upgrade', '20261106-120000', 'config', 'book.yml')),
                 'vs upgrade の退避を消してはいけません'
          %w[frontcover_master.png backcover_photo.jpg frontcover_hand_drawn.pdf].each do |name|
            assert File.exist?(File.join('covers', name)), "covers/#{name} は著者ソースなので保持されるべきです"
          end
        end
      end

      # --index-dictionaries は 3 つの辞書（terms/rejected/読みの個人辞書）だけを削除し、キャッシュには触れない
      def test_should_remove_only_the_dictionaries_with_index_dictionaries
        within_temp_dir do
          setup_cache_files
          FileUtils.mkdir_p('config')
          %w[index_glossary_terms.yml index_glossary_rejected.yml index_yomi_overrides.yml].each do |name|
            write_file(File.join('config', name))
          end

          summary = nil
          with_stdin("y\n") do
            capture_io { summary = CleanCommands.execute_clean({ index_dictionaries: true }) }
          end

          refute File.exist?('config/index_glossary_terms.yml'), '登録済み用語辞書は削除されるべきです'
          refute File.exist?('config/index_glossary_rejected.yml'), '除外用語辞書は削除されるべきです'
          refute File.exist?('config/index_yomi_overrides.yml'), '読みの個人辞書は削除されるべきです'
          assert Dir.exist?(VivlioStarter::CLI::Common.cache_dir), '辞書だけの指定ではキャッシュを残すべきです'
          assert_equal 3, summary.dictionaries
          assert_equal 0, summary.cache
        end
      end

      # 確認で「いいえ」と答えたら辞書を残す
      def test_should_keep_the_dictionaries_when_declined
        within_temp_dir do
          write_file(File.join('config', 'index_glossary_terms.yml'))

          with_stdin("n\n") do
            capture_io { CleanCommands.execute_clean({ index_dictionaries: true }) }
          end

          assert File.exist?('config/index_glossary_terms.yml')
        end
      end

      # vs build・vs preflight・章番号の付け直しの後始末。作業フォルダだけを消し、
      # キャッシュと著者の持ち物には触れない
      def test_should_remove_only_the_build_workspace_after_a_build
        within_temp_dir do
          setup_generated_files
          setup_cache_files
          write_file(File.join('contents', '11-sample.md'))

          CleanCommands.clean_build_workspace

          refute Dir.exist?(VivlioStarter::CLI::Common::BUILD_DIR), 'ビルドワークスペースは削除されるべきです'
          assert File.exist?(File.join(VivlioStarter::CLI::Common.cover_cache_dir, 'cover.jpg')),
                 '生成した表紙のキャッシュは残すべきです'
          assert File.exist?(File.join('.cache', 'metrics', '11-sample.yml')), 'metrics のキャッシュは残すべきです'
          assert_author_files_intact
          assert_final_pdfs_exist
          assert File.exist?(File.join('contents', '11-sample.md')), '原稿を消してはいけません'
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

      # キャッシュ一式。.cache/vs/ の生成画像（表紙・扉絵）と、.cache/metrics/ のキャッシュ
      def setup_cache_files
        write_file(File.join(VivlioStarter::CLI::Common.cover_cache_dir, 'cover.jpg'))
        write_file(File.join(VivlioStarter::CLI::Common.theme_images_cache_dir, 'chapter.webp'))
        write_file(File.join('.cache', 'metrics', '11-sample.yml'))
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
    end
  end
end
