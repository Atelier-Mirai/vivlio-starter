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
#
# 依存:
#   - HexaPDF: PDF メタデータ読み取り
#   - pdfinfo: ページ数取得（外部コマンド）
# ================================================================

require 'hexapdf'

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

          # PDF のページ数を取得（pdfinfo が必要）
          def page_count(file)
            return nil unless File.exist?(file)

            if system('which pdfinfo >/dev/null 2>&1')
              info = `pdfinfo "#{file}" 2>/dev/null`
              pages = info[/^Pages:\s+(\d+)/i, 1]
              return pages if pages
            end
            nil
          end

          # 1..89 範囲の章番号（整数）の配列を返す（新仕様）
          def chapter_numbers_for_book(keep = nil)
            basenames = if keep&.any?
                          Array(keep).map { |s| File.basename(s.to_s, '.md') }
                        else
                          Dir[File.join(Common::CONTENTS_DIR, '*.md')].map { |p| File.basename(p, '.md') }
                        end
            basenames
              .map { |bn| Common.get_chapter_number(bn) }
              .compact
              .map(&:to_i)
              .select { |n| n.between?(1, 89) }
              .uniq
              .sort
          end

          # PDF アウトライン生成対象の章番号リストを取得（新仕様）
          def chapter_numbers_for_outline(keep = nil)
            # 新仕様: 0=PREFACE, 1-89=CHAPTERS, 90-98=APPENDICES, 99=POSTFACE
            allowed_numbers = [0, 99] + (1..89).to_a + (90..98).to_a
            basenames = if keep&.any?
                          Array(keep).map do |entry|
                            name = File.basename(entry.to_s)
                            name.sub(/\.[^.]+\z/, '')
                          end
                        else
                          md = Dir[File.join(Common::CONTENTS_DIR, '*.md')].map { |p| File.basename(p, '.md') }
                          html = Dir[File.join('.', '*.html')].map { |p| File.basename(p, '.html') }
                          (md + html)
                        end

            numbers = basenames
                      .map { |bn| Common.get_chapter_number(bn) }
                      .compact
                      .map(&:to_i)
                      .select { |n| allowed_numbers.include?(n) }

            # TOC (_toc.html) はアウトライン生成時に別途処理されるため、ここでは追加不要

            numbers.uniq!
            numbers.sort!
            numbers
          end

          # 空白1ページPDFを生成
          def ensure_blank_page_pdf(path = 'blank_page.pdf')
            return path if File.exist?(path)

            doc = HexaPDF::Document.new
            w_pt, h_pt = Build::Utilities.page_size_points_from_config
            doc.pages.add([0, 0, w_pt, h_pt])
            doc.write(path, optimize: true)
            path
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

          # qpdf で PDF を分割（旧仕様: 後方互換用）
          def split_pdf_into_toc_and_sections(output_pdf, frontmatter_pages, front_pdf, body_pdf)
            split_pdf_into_frontmatter_and_sections(output_pdf, frontmatter_pages, front_pdf, body_pdf)
          end

          # qpdf で PDF を frontmatter と sections に分割
          # 新仕様: frontmatter（前書き+目次）が先頭にある場合の分割
          def split_pdf_into_frontmatter_and_sections(output_pdf, frontmatter_pages, front_pdf, body_pdf)
            total_pages = (page_count(output_pdf) || '0').to_i
            if total_pages <= 0
              Common.log_warn("[Step 7] 総ページ数の取得に失敗しました: #{output_pdf}")
              return false
            end

            unless system('which qpdf >/dev/null 2>&1')
              Common.log_warn('[Step 7] qpdf が見つかりません。`brew install qpdf` でインストールしてください。')
              return false
            end

            FileUtils.rm_f(front_pdf)
            FileUtils.rm_f(body_pdf)

            ok1 = ok2 = true

            # frontmatter（前書き+目次）を先頭から抽出
            if frontmatter_pages.positive?
              Common.log_action("[Step 7] frontmatter を抽出しています (1-#{frontmatter_pages})…")
              ok1 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" 1-#{frontmatter_pages} -- "#{front_pdf}" > /dev/null))
            else
              Common.log_warn('[Step 7] frontmatter のページがありません。')
            end

            # sections（本文+付録+後書き+索引）を後方から抽出
            body_start = frontmatter_pages + 1
            if body_start <= total_pages
              Common.log_action("[Step 7] sections を抽出しています (#{body_start}-z)…")
              ok2 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" #{body_start}-z -- "#{body_pdf}" > /dev/null))
            else
              Common.log_warn('[Step 7] sections のページがありません。frontmatter が全ページを占めています。')
            end

            if ok1 && ok2
              Common.log_success("[Step 7] 分割完了: #{front_pdf}, #{body_pdf}")
              true
            else
              Common.log_warn('[Step 7] PDF の分割に失敗しました (qpdf 実行エラー)')
              false
            end
          end

          # 廃止されたメソッド
          def update_css_counter(_css_path, _number)
            Common.log_info('update_css_counter は廃止されました。処理をスキップします。')
            false
          end
        end
      end
    end
  end
end
