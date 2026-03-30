# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build/epub_builder.rb
# ================================================================
# 責務:
#   EPUB 出力に必要な中間ファイルを生成する。
#   - EPUB 専用 entries.js（目次・裏表紙を除外）
#   - EPUB 専用 vivliostyle.config.js（cover / output を EPUB 用に調整）
#
# 仕様書: docs/specs/epub_output_spec.md
#
# 設計方針:
#   - PDF 用の vivliostyle.config.js を直接書き換えず、
#     EPUB 専用の設定ファイル vivliostyle.config.epub.js を生成する。
#   - これにより PDF ビルドへの副作用を完全に排除する。
# ================================================================

require 'fileutils'
require_relative '../entries'

module Vivlio
  module Starter
    module CLI
      module Build
        # EPUB ビルド用の中間ファイル生成モジュール
        module EpubBuilder
          # EPUB 専用設定ファイル名
          EPUB_CONFIG_FILE  = 'vivliostyle.config.epub.js'
          # EPUB 専用 entries ファイル名
          EPUB_ENTRIES_FILE = 'entries.epub.js'
          # EPUB デフォルト出力ファイル名
          EPUB_OUTPUT_FILE  = 'output.epub'

          # EPUB で除外する特殊ページ
          # 目次は EPUB リーダーが自動生成するため不要
          EXCLUDED_BASENAMES = %w[_toc].freeze

          module_function

          # EPUB 用 entries.js を生成する
          # PDF 用の構成から目次・裏表紙を除外した EPUB 専用エントリを生成
          #
          # @param base_dir [String] ベースディレクトリ
          # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
          # @return [Array<String>] EPUB に含める HTML ファイルパスの配列
          def generate_epub_entries!(base_dir, entries)
            Common.log_action('[EPUB] entries.epub.js を生成しています…')

            chapter_htmls = collect_epub_htmls(base_dir, entries)

            if chapter_htmls.empty?
              Common.log_warn('[EPUB] 対象 HTML が見つかりません。スキップします。')
              return []
            end

            # 索引・用語集を EPUB 用に書き換え（空リンクに連番テキストを挿入）
            post_process_index_glossary_for_epub!(chapter_htmls)

            write_epub_entries(base_dir, chapter_htmls)
            Common.log_success("[EPUB] entries.epub.js を生成しました（#{chapter_htmls.size} エントリ）")
            chapter_htmls
          end

          # EPUB 専用 vivliostyle.config.js を生成する
          # cover.embed 設定に応じて表紙画像の埋め込みを制御
          #
          # @return [String] 生成されたファイルパス
          def generate_epub_config!
            Common.log_action('[EPUB] vivliostyle.config.epub.js を生成しています…')

            config = Common::CONFIG
            book_config = config.book

            # JS 文字列に安全に埋め込むための簡易エスケープ
            esc = ->(s) { s.to_s.gsub('\\', '\\\\').gsub("'", "\\'") }

            # メタデータを book セクションから取得
            # book.title は存在しない場合がある（main_title + subtitle から合成）
            combined_title = [book_config&.main_title, book_config&.subtitle].compact.join(' ').strip
            title_raw = book_config&.respond_to?(:title) ? book_config.title : nil
            title = if title_raw && !title_raw.to_s.strip.empty?
                      title_raw
                    else
                      combined_title.empty? ? '書籍タイトル' : combined_title
                    end
            author   = book_config&.author || '著者名'
            language = book_config&.language || 'ja'

            # ページサイズを解決（vivliostyle.rb から移植）
            page_size = resolve_page_size(config)

            # 表紙画像の埋め込み設定を取得
            cover_line = build_cover_config_line(config, esc)

            # 横書き固定（将来の縦書き対応に備えてハードコーディング）
            reading_progression = 'ltr'

            config_content = <<~JS
              import entries from './#{EPUB_ENTRIES_FILE}';

              // @ts-check
              // EPUB 専用設定ファイル（自動生成・編集不要）
              /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
              const vivliostyleConfig = {
                title: '#{esc.call(title)}',
                author: '#{esc.call(author)}',
                language: '#{esc.call(language)}',
                size: '#{esc.call(page_size)}',
                readingProgression: '#{esc.call(reading_progression)}',
              #{cover_line}  entry: entries,
                output: [
                  './#{EPUB_OUTPUT_FILE}'
                ]
              };

              export default vivliostyleConfig;
            JS

            File.write(EPUB_CONFIG_FILE, config_content)
            Common.log_success("[EPUB] #{EPUB_CONFIG_FILE} を生成しました")
            EPUB_CONFIG_FILE
          end

          # EPUB に含める HTML ファイルを収集する
          # PDF 向けの構成から目次・裏表紙を除外
          #
          # @param base_dir [String] ベースディレクトリ
          # @param entries [Array<TokenResolver::Entry>] Entry 配列
          # @return [Array<String>] HTML ファイルパスの配列
          def collect_epub_htmls(base_dir, entries)
            keep_numbers_main = Build::Utilities.chapter_numbers_for_book(entries)
            keep_numbers_appx = nil
            keep_numbers_post = nil

            if entries&.any?
              chapter_numbers = PdfBuilder.send(:extract_chapter_numbers, entries)
              keep_numbers_appx = chapter_numbers.select { |n| PdfBuilder::APPX_RANGE.include?(n) }
              keep_numbers_post = chapter_numbers.select { |n| PdfBuilder::POSTFACE_RANGE.include?(n) }
            end

            # 前書き（00-preface）
            preface_html = [File.join(base_dir, '00-preface.html')].select { File.exist?(it) }

            # 本文章 HTML（中扉を挿入）
            main_htmls = Build::ChapterConfig.htmls_for_range(base_dir, PdfBuilder::MAIN_RANGE, keep_numbers_main)
            main_htmls_with_parts = Build::PartTitleGenerator.insert_part_titles_into(main_htmls, base_dir)

            # 付録
            appx_htmls = Build::ChapterConfig.htmls_for_range(base_dir, PdfBuilder::APPX_RANGE, keep_numbers_appx)

            # 用語集・索引（リフロー型ではページ番号は無意味だがリンクは有効）
            glossary_html = if IndexCommands.index_enabled?
                              [File.join(base_dir, '_glossarypage.html')].select { File.exist?(it) }
                            else
                              []
                            end

            # 後書き
            post_htmls = Build::ChapterConfig.htmls_for_range(base_dir, PdfBuilder::POSTFACE_RANGE, keep_numbers_post)

            # 索引
            index_html = if IndexCommands.index_enabled?
                           [File.join(base_dir, '_indexpage.html')].select { File.exist?(it) }
                         else
                           []
                         end

            # 書籍構成順序: 前書き → [中扉+本文] → 付録 → 用語集 → 後書き → 索引
            # ※ 目次（_toc）と裏表紙は除外
            [
              preface_html,
              main_htmls_with_parts,
              appx_htmls,
              glossary_html,
              post_htmls,
              index_html
            ].flatten.reject { excluded_basename?(it) }
          end

          # EPUB 用 entries.js をファイルに書き出す
          #
          # @param base_dir [String] ベースディレクトリ
          # @param html_files [Array<String>] HTML ファイルパスの配列
          def write_epub_entries(base_dir, html_files)
            entries = html_files.map { CLI::EntriesCommands.build_entry(it) }

            File.open(File.join(base_dir, EPUB_ENTRIES_FILE), 'w') do |f|
              f.puts 'export default ['
              entries.each_with_index do |entry, i|
                f.puts '  {'
                f.puts %(    "path": "#{entry[:path]}",)
                f.puts %(    "title": "#{entry[:title]}")
                f.puts "  }#{',' if i < entries.length - 1}"
              end
              f.puts ']'
            end
          end

          # 除外対象の basename かどうかを判定する
          #
          # @param html_path [String] HTML ファイルパス
          # @return [Boolean]
          def excluded_basename?(html_path)
            basename = File.basename(html_path, '.html')
            EXCLUDED_BASENAMES.include?(basename)
          end

          # cover 設定行を生成する
          # 新しい設定構造に対応
          #
          # @param config [Object] Common::CONFIG
          # @param esc [Proc] JS エスケープ用 Proc
          # @return [String] cover 設定行（末尾改行付き）
          # EPUB 表紙埋め込みが有効かどうかを判定
          # @param epub_cfg [Object] epub設定オブジェクト（cover.embed を持つ）
          # @return [Boolean]
          def embed_cover?(epub_cfg)
            epub_cfg&.cover&.embed != false
          end

          def build_cover_config_line(config, esc)
            return "  // cover: 表紙埋め込みなし（epub.embed: false）\n" unless Common.epub_embed?

            cover_image = resolve_cover_image_path(config)
            return "  // cover: 表紙画像が見つかりません\n" unless cover_image && File.exist?(cover_image)

            "  cover: './#{esc.call(cover_image)}',\n"
          end

          # 表紙画像のパスを解決する
          # 新しい設定構造に対応
          #
          # @param config [Object] Common::CONFIG
          # @return [String, nil] 表紙画像の相対パス
          def resolve_cover_image_path(config)
            covers_dir = config.directories&.covers || 'covers'
            theme = Common.cover_theme
            return nil unless theme
            
            image_name = "cover_#{theme}.jpg"
            File.join(covers_dir, image_name)
          end

          # book.yml のページ設定から Vivliostyle CLI 用サイズ文字列を解決する
          # vivliostyle.rb の resolve_vivliostyle_size から移植
          #
          # @param config [Object] Common::CONFIG
          # @return [String] 'A5', 'B5', 'A4', または '148mm 210mm' 形式
          def resolve_page_size(config)
            page_cfg = config.respond_to?(:page) ? config.page : config[:page]
            return 'A5' unless page_cfg

            size_name = page_cfg[:size].to_s.strip.upcase
            return size_name unless size_name.empty?

            raw = page_cfg.respond_to?(:to_h) ? page_cfg.to_h : page_cfg
            w, h = Common.resolve_page_size(raw)
            "#{w} #{h}"
          end

          # ================================================================
          # EPUB 用 索引・用語集 後処理
          # ================================================================
          # CSS target-counter() は EPUB リーダーで非対応のため、
          # 空の <a> タグにテキストを挿入して可視化する。
          # PDF ビルド完了後に元ファイルを直接修正する方式。
          # （コピーを作ると本文中の †リンクが _glossarypage.html を参照して切れるため）
          # ================================================================

          # 索引・用語集 HTML を EPUB 用に直接修正する
          # ファイル名プレフィックス（00, 08, 11 等）を書籍構成順の連番（0, 1, 2 等）に変換
          #
          # @param html_files [Array<String>] HTML ファイルパスの配列（書籍構成順）
          # @return [Array<String>] そのままの配列（パス変更なし）
          def post_process_index_glossary_for_epub!(html_files)
            chapter_map = build_sequential_chapter_map(html_files)

            html_files.each do |path|
              basename = File.basename(path, '.html')
              case basename
              when '_indexpage'
                rewrite_index_for_epub!(path, chapter_map)
              when '_glossarypage'
                rewrite_glossary_for_epub!(path, chapter_map)
              end
            end
            html_files
          end

          # HTML ファイルの構成順から、ファイル名プレフィックス → 連番 のマッピングを構築
          # 例: { "00" => 0, "08" => 1, "11" => 2, "21" => 3, "91" => 4, "99" => 5 }
          #
          # @param html_files [Array<String>] 書籍構成順の HTML ファイルパス
          # @return [Hash{String => Integer}] プレフィックス → 連番
          def build_sequential_chapter_map(html_files)
            mapping = {}
            seq = 0
            html_files.each do |path|
              basename = File.basename(path, '.html')
              next unless basename.match?(/\A\d{2}-/)

              prefix = basename[0, 2]
              unless mapping.key?(prefix)
                mapping[prefix] = seq
                seq += 1
              end
            end
            Common.log_info("[EPUB] 章番号マッピング: #{mapping.map { |k, v| "#{k}→#{v}" }.join(', ')}")
            mapping
          end

          # 索引 HTML を EPUB 用に書き換える
          # - 空リンクに連番の章番号を挿入
          # - 連続するリンク間に ", " 区切りを追加
          #
          # @param path [String] _indexpage.html のパス
          # @param chapter_map [Hash{String => Integer}] プレフィックス → 連番
          def rewrite_index_for_epub!(path, chapter_map)
            html = File.read(path, encoding: 'utf-8')

            # Step 1: 空の <a> タグに連番の章番号を挿入
            html = html.gsub(%r{(<a\s+href="(\d{2})[^"]*"[^>]*)>\s*</a>}) do
              tag_open = ::Regexp.last_match(1)
              prefix = ::Regexp.last_match(2)
              chapter_num = chapter_map[prefix] || prefix.to_i
              "#{tag_open}>#{chapter_num}</a>"
            end

            # Step 2: 連続する </a><a を </a>, <a に変換（カンマ区切り）
            html = html.gsub(%r{</a>\s*(<a\s+href=")}, '</a>, \1')

            File.write(path, html, encoding: 'utf-8')
            Common.log_info("[EPUB] #{File.basename(path)} を書き換えました（連番リンク＋区切り挿入）")
          end

          # 用語集 HTML を EPUB 用に書き換える
          # - 空バックリンクに連番の章番号を挿入
          #   CSS の ::before が "→ p." を付加するため記号は不要
          #
          # @param path [String] _glossarypage.html のパス
          # @param chapter_map [Hash{String => Integer}] プレフィックス → 連番
          def rewrite_glossary_for_epub!(path, chapter_map)
            html = File.read(path, encoding: 'utf-8')

            # 空の <a> タグに連番の章番号を挿入
            html = html.gsub(%r{(<a\s+href="(\d{2})[^"]*"[^>]*)>\s*</a>}) do
              tag_open = ::Regexp.last_match(1)
              prefix = ::Regexp.last_match(2)
              chapter_num = chapter_map[prefix] || prefix.to_i
              "#{tag_open}>#{chapter_num}</a>"
            end

            File.write(path, html, encoding: 'utf-8')
            Common.log_info("[EPUB] #{File.basename(path)} を書き換えました（連番バックリンク挿入）")
          end

          # EPUB 中間ファイルをクリーンアップする
          #
          # @return [void]
          def cleanup!
            [EPUB_CONFIG_FILE, EPUB_ENTRIES_FILE, EPUB_OUTPUT_FILE].each do |file|
              next unless File.exist?(file)

              FileUtils.rm_f(file)
              Common.log_info("[EPUB] #{file} を削除しました")
            end
          end
        end
      end
    end
  end
end
