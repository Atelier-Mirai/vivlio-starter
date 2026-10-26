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
#   入稿用しおりが目次へ集中する不具合の原因になっていたため廃止した。しおりのページは、
#   注釈対象 PDF の見出しの飛び先から引く（OutlineExtractor・pdf-outline-heading-id-spec.md）。
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
        module_function

        # Step 6: TOC HTML を生成する（pdf / print_pdf 共通）。
        # 見出しメタ（PDF アウトライン用）まで付与した _toc.html を生成する。
        # @param base_dir [String] ベースディレクトリ
        # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil]
        def generate_toc_html!(base_dir = '.', entries_or_keep = nil)
          targets_for_toc = %i[preface chapter appendix postface].flat_map do
            Build::ChapterConfig.htmls_for_kind(base_dir, it, entries_or_keep)
          end.uniq

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
      end
    end
  end
end
