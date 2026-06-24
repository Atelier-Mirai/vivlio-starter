# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/toc_generator.rb
# ================================================================
# 責務:
#   目次（Table of Contents）の HTML を生成する。
#
# 生成ファイル:
#   - _toc.md: 目次 Markdown
#   - _toc.html: 目次 HTML（VFM 変換後）
#
# NOTE: かつて補助 PDF `_toc.pdf` も生成していたが、これは結合（merge）には使われず、
#   アウトラインのページ計算専用の副産物だった。print_pdf 単独ビルドでは生成されず
#   入稿用しおりが目次へ集中する不具合の原因になっていたため廃止し、ページ計算は
#   注釈対象 PDF からのテキスト検出（OutlineExtractor）へ移した。
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

module VivlioStarter
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

        # Step 6: TOC HTML を生成する（pdf / print_pdf 共通）。
        # 見出しメタ（PDF アウトライン用）まで付与した _toc.html を生成する。
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
