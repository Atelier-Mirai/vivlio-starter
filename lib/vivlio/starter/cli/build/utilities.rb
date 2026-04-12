# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build/utilities.rb
# ================================================================
# 責務:
#   ビルドパイプラインで使用する共通ユーティリティを提供する。
#
# 提供機能:
#   - キャッシュ管理: ファイルの保存・復元
#   - PDF 操作: ページ数取得、ページサイズ計算
#   - 章番号計算: keep オプション用の番号抽出
#   - 判型計算: config からページサイズを算出
#
# 依存:
#   - pdfinfo: ページ数取得（外部コマンド）
#   - Provider (Prawn + CombinePDF): PDF 操作（MIT互換）
# ================================================================

require 'fileutils'

module Vivlio
  module Starter
    module CLI
      module Build
        # ビルド共通ユーティリティモジュール
        module Utilities
          module_function

          # キャッシュにファイルを保存
          def cache_store_file(cache_on, source, dest, step_label)
            return false unless cache_on && source && dest && File.exist?(source)

            FileUtils.cp(source, dest)
            Common.log_info("[#{step_label}] キャッシュへ保存しました: #{dest}")
            true
          end

          # キャッシュからファイルを復元
          def cache_restore_file(cache_on, source, dest, step_label)
            return false unless cache_on && source && File.exist?(source) && dest && !File.exist?(dest)

            FileUtils.cp(source, dest)
            Common.log_info("[#{step_label}] キャッシュから復元しました: #{dest}")
            true
          end

          # PDF のページ数を取得（pdfinfo → HexaPDF フォールバック → MIT版へ変更）
          def page_count(file)
            return nil unless File.exist?(file)

            # pdfinfo を優先
            if system('which pdfinfo >/dev/null 2>&1')
              info = `pdfinfo "#{file}" 2>/dev/null`
              pages = info[/^Pages:\s+(\d+)/i, 1]
              return pages.to_i if pages
            end

            # 新実装 (MIT版 Provider への委譲)
            require 'vivlio/starter/cli/pdf/provider'
            Vivlio::Starter::Pdf.provider.page_count(file)

            # --- 旧実装（MIT化動作確認後に削除予定） ---
            # doc = HexaPDF::Document.open(file)
            # doc.pages.count
          rescue StandardError
            nil
          end

          # 複数 PDF の合計ページ数を返す
          def total_page_count(files)
            files.sum { |f| page_count(f).to_i }
          end

          # 1..89 範囲の章番号（整数）の配列を返す（新仕様）
          # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil] Entry 配列または basename 配列
          # @return [Array<Integer>] 1..89 範囲の章番号配列
          def chapter_numbers_for_book(entries_or_keep = nil)
            entries = resolve_entries(entries_or_keep)
            entries
              .filter_map { it.number&.to_i }
              .select { it.between?(1, 89) }
              .uniq
              .sort
          end

          # PDF アウトライン生成対象の章番号リストを取得（新仕様）
          # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil] Entry 配列または basename 配列
          # @return [Array<Integer>] アウトライン対象の章番号配列
          def chapter_numbers_for_outline(entries_or_keep = nil)
            # 新仕様: 0=PREFACE, 1-89=CHAPTERS, 90-98=APPENDICES, 99=POSTFACE
            allowed_numbers = [0, 99] + (1..89).to_a + (90..98).to_a
            entries = resolve_entries(entries_or_keep)

            numbers = entries
                      .filter_map { it.number&.to_i }
                      .select { allowed_numbers.include?(it) }

            # TOC (_toc.html) はアウトライン生成時に別途処理されるため、ここでは追加不要

            numbers.uniq!
            numbers.sort!
            numbers
          end

          # Entry 配列または basename 配列から basename 配列を抽出
          # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil]
          # @return [Array<String>] basename 配列
          def extract_basenames(entries_or_keep)
            raw = Array(entries_or_keep).compact
            return [] if raw.empty?

            if raw.first.respond_to?(:basename)
              raw.map(&:basename)
            else
              raw.map { |s| File.basename(s.to_s, '.md') }
            end
          end

          # Entry 配列または basename 配列を Entry 配列に解決
          # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil]
          # @return [Array<TokenResolver::Entry>]
          def resolve_entries(entries_or_keep)
            raw = Array(entries_or_keep).compact
            if raw.empty?
              # 全ファイルを解決
              resolver = TokenResolver::Resolver.new
              Dir[File.join(Common::CONTENTS_DIR, '*.md')].map { resolver.resolve_file(it) }
            elsif raw.first.respond_to?(:kind)
              raw
            else
              resolver = TokenResolver::Resolver.new
              raw.map { resolver.resolve_file(it) }
            end
          end

          # 空白1ページPDFを生成
          def ensure_blank_page_pdf(path = 'blank_page.pdf')
            return path if File.exist?(path)

            w_pt, h_pt = Build::Utilities.page_size_points_from_config
            require 'vivlio/starter/cli/pdf/provider'
            Vivlio::Starter::Pdf.provider.ensure_blank_page_pdf(path, w_pt, h_pt)

            # --- 旧実装（MIT化動作確認後に削除予定） ---
            # doc = HexaPDF::Document.new
            # w_pt, h_pt = Build::Utilities.page_size_points_from_config
            # doc.pages.add([0, 0, w_pt, h_pt])
            # doc.write(path, optimize: true)
            # path
          end

          # 現在の設定からページサイズ（文字列: mm/pt）を取得
          def page_size_strings_from_config
            page_cfg = Common::CONFIG['page'] || {}
            result = Common.resolve_page_size(page_cfg)
            if result.is_a?(Array) && result.size == 2 && result.all? do |dim|
              dim.to_s.strip.match?(/\A[0-9.]+(mm|pt)?\z/)
            end
              result
            else
              %w[182mm 257mm]
            end
          end

          # 現在の設定からページサイズ（pt）を取得
          def page_size_points_from_config
            width_s, height_s = page_size_strings_from_config
            mm_to_pt = 72.0 / 25.4
            parse_len = lambda { |s|
              str = s.to_s.strip.downcase
              if str.end_with?('mm')
                str.sub(/mm\z/, '').to_f * mm_to_pt
              elsif str.end_with?('pt')
                str.sub(/pt\z/, '').to_f
              else
                str.to_f
              end
            }
            w_pt = parse_len.call(width_s)
            h_pt = parse_len.call(height_s)
            if w_pt <= 0 || h_pt <= 0 || w_pt.nan? || h_pt.nan?
              w_pt = 182.0 * mm_to_pt
              h_pt = 257.0 * mm_to_pt
            end
            [w_pt, h_pt]
          end

          # PDF 操作は Provider 経由で MIT 互換ライブラリ（Prawn + CombinePDF）に委譲
        end
      end
    end
  end
end
