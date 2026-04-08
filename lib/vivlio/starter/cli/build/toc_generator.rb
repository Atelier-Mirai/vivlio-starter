# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build/toc_generator.rb
# ================================================================
# 責務:
#   目次（Table of Contents）の HTML/PDF を生成する。
#
# 生成ファイル:
#   - _toc.md: 目次 Markdown
#   - _toc.html: 目次 HTML（VFM 変換後）
#   - _toc.pdf: 目次 PDF（単独ビルド用）
#
# 章構成:
#   - PREFACE (00): 前書き
#   - MAIN (01-89): 本文
#   - APPENDICES (90-98): 付録
#   - POSTFACE (99): 後書き
#
# 依存:
#   - TocCommands: 目次生成の実装
#   - ChapterConfig: 章ファイルの解決
# ================================================================

require_relative '../toc'

module Vivlio
  module Starter
    module CLI
      module Build
        # 目次生成モジュール
        module TocGenerator
          # 章レンジ（定数）- 新仕様に合わせて更新
          PREFACE_RANGE  = (0..0)   # 00-preface
          MAIN_RANGE     = (1..89)  # 01..89 本文
          APPX_RANGE     = (90..98) # 90..98 付録
          POSTFACE_RANGE = (99..99) # 99-postface

          module_function

          # Step 6: TOC 生成（_toc.html, _toc.pdf）
          # @param base_dir [String] ベースディレクトリ
          # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil] Entry 配列または basename 配列
          def generate_toc_and_pdf!(base_dir = '.', entries_or_keep = nil)
            keep_numbers_main = Build::Utilities.chapter_numbers_for_book(entries_or_keep)
            # 前書き、付録、後書きの keep を抽出
            keep_numbers_preface = nil
            keep_numbers_appx = nil
            keep_numbers_post = nil
            if entries_or_keep&.any?
              chapter_numbers = extract_chapter_numbers(entries_or_keep)
              keep_numbers_preface = chapter_numbers.select { |n| PREFACE_RANGE.include?(n) }
              keep_numbers_appx = chapter_numbers.select { |n| APPX_RANGE.include?(n) }
              keep_numbers_post = chapter_numbers.select { |n| POSTFACE_RANGE.include?(n) }
            end
            # base_dir 内の HTML から前書き(00) + 本文(01..89) + 付録(90..98) + 後書き(99) を抽出
            chapter_htmls_preface = Build::ChapterConfig.htmls_for_range(base_dir, PREFACE_RANGE, keep_numbers_preface)
            chapter_htmls_main = Build::ChapterConfig.htmls_for_range(base_dir, MAIN_RANGE, keep_numbers_main)
            chapter_htmls_appx = Build::ChapterConfig.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx)
            chapter_htmls_post = Build::ChapterConfig.htmls_for_range(base_dir, POSTFACE_RANGE, keep_numbers_post)
            targets_for_toc = (chapter_htmls_preface + chapter_htmls_main + chapter_htmls_appx + chapter_htmls_post).uniq.sort

            if targets_for_toc.empty?
              Common.log_warn('[Step 5] 対象HTMLが見つかりません。スキップします。')
              return
            end

            Common.log_info("[Step 5] 対象: #{targets_for_toc.map { |p| File.basename(p) }.join(', ')}")
            TocCommands.execute_toc({}, targets_for_toc)
            toc_html = File.join(base_dir, '_toc.html')
            unless File.exist?(toc_html)
              Common.log_warn('[Step 5] _toc.html が見つかりません。TOC の PDF 生成をスキップします。')
              return
            end
            # TOC も post_process を適用して見出しメタを付与（PDFアウトライン用）
            PostProcessCommands.execute_post_process({}, ['_toc'])
            Common.log_info('[Step 5] _toc.html に post_process を適用しました（見出しメタ付与）')
            EntriesCommands.execute_entries({}, ['_toc'])
            # 改良された pdf コマンドに出力ファイル名を渡してリネームも一括処理
            PdfCommands.execute_pdf({}, '_toc.pdf')
            Common.log_success('[Step 5] _toc.pdf を生成しました') if File.exist?('_toc.pdf')
          end

          # Step 6 (print_pdf only): TOC HTML のみ生成（_toc.pdf ビルドをスキップ）
          # @param base_dir [String] ベースディレクトリ
          # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil]
          def generate_toc_html!(base_dir = '.', entries_or_keep = nil)
            keep_numbers_main = Build::Utilities.chapter_numbers_for_book(entries_or_keep)
            keep_numbers_preface = nil
            keep_numbers_appx = nil
            keep_numbers_post = nil
            if entries_or_keep&.any?
              chapter_numbers = extract_chapter_numbers(entries_or_keep)
              keep_numbers_preface = chapter_numbers.select { |n| PREFACE_RANGE.include?(n) }
              keep_numbers_appx = chapter_numbers.select { |n| APPX_RANGE.include?(n) }
              keep_numbers_post = chapter_numbers.select { |n| POSTFACE_RANGE.include?(n) }
            end
            chapter_htmls_preface = Build::ChapterConfig.htmls_for_range(base_dir, PREFACE_RANGE, keep_numbers_preface)
            chapter_htmls_main = Build::ChapterConfig.htmls_for_range(base_dir, MAIN_RANGE, keep_numbers_main)
            chapter_htmls_appx = Build::ChapterConfig.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx)
            chapter_htmls_post = Build::ChapterConfig.htmls_for_range(base_dir, POSTFACE_RANGE, keep_numbers_post)
            targets_for_toc = (chapter_htmls_preface + chapter_htmls_main + chapter_htmls_appx + chapter_htmls_post).uniq.sort

            if targets_for_toc.empty?
              Common.log_warn('[Step 6] 対象HTMLが見つかりません。スキップします。')
              return
            end

            TocCommands.execute_toc({}, targets_for_toc)
            toc_html = File.join(base_dir, '_toc.html')
            unless File.exist?(toc_html)
              Common.log_warn('[Step 6] _toc.html が見つかりません。')
              return
            end
            PostProcessCommands.execute_post_process({}, ['_toc'])
            Common.log_success('[Step 6] _toc.html を生成しました（PDF ビルドはスキップ）')
          end

          # Entry 配列または basename 配列から章番号配列を抽出
          # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>]
          # @return [Array<Integer>] 章番号配列
          def extract_chapter_numbers(entries_or_keep)
            raw = Array(entries_or_keep).compact
            return [] if raw.empty?

            if raw.first.respond_to?(:number)
              raw.filter_map { it.number&.to_i }
            else
              resolver = TokenResolver::Resolver.new
              raw.filter_map { resolver.resolve_file(it).number&.to_i }
            end
          end
        end
      end
    end
  end
end
