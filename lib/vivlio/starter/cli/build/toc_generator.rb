# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # TocGenerator: 目次生成モジュール
        # ------------------------------------------------
        # TOCのHTML/PDF生成を担当する。
        # ------------------------------------------------
        module TocGenerator
          # 章レンジ（定数）
          PREFACE_RANGE  = (2..2)
          MAIN_RANGE     = (11..89)
          APPX_RANGE     = (91..97)
          POSTFACE_RANGE = (98..98)

          module_function

          # Step 6: TOC 生成（03-toc.html, 03-toc.pdf）
          def generate_toc_and_pdf!(base_dir = '.', keep = nil)
            keep_numbers_main = Build::Utilities.chapter_numbers_for_book(keep)
            # 前書き、付録、後書きの keep を抽出
            keep_numbers_preface = nil
            keep_numbers_appx = nil
            keep_numbers_post = nil
            if keep&.any?
              normalized_keep = Array(keep)
                                .map { |s| File.basename(s.to_s, '.md') }
              chapter_numbers = normalized_keep
                                .map { |bn| Common.get_chapter_number(bn) }
                                .compact.map(&:to_i)
              keep_numbers_preface = chapter_numbers.select { |n| PREFACE_RANGE.include?(n) }
              keep_numbers_appx = chapter_numbers.select { |n| APPX_RANGE.include?(n) }
              keep_numbers_post = chapter_numbers.select { |n| POSTFACE_RANGE.include?(n) }
            end
            # base_dir 内の HTML から前書き(02) + 本文(11..89) + 付録(91..97) + 後書き(98) を抽出
            chapter_htmls_preface = Build::ChapterConfig.htmls_for_range(base_dir, PREFACE_RANGE, keep_numbers_preface)
            chapter_htmls_main = Build::ChapterConfig.htmls_for_range(base_dir, MAIN_RANGE, keep_numbers_main)
            chapter_htmls_appx = Build::ChapterConfig.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx)
            chapter_htmls_post = Build::ChapterConfig.htmls_for_range(base_dir, POSTFACE_RANGE, keep_numbers_post)
            targets_for_toc = (chapter_htmls_preface + chapter_htmls_main + chapter_htmls_appx + chapter_htmls_post).uniq.sort

            if targets_for_toc.empty?
              Common.log_warn('[Step 6] 対象HTMLが見つかりません。Step 6 をスキップします。')
              return
            end

            Common.log_info("[Step 6] 対象: #{targets_for_toc.map { |p| File.basename(p) }.join(', ')}")
            Vivlio::Starter::ThorCLI.start(['toc', *targets_for_toc])
            toc_html = File.join(base_dir, '03-toc.html')
            unless File.exist?(toc_html)
              Common.log_warn('[Step 6] 03-toc.html が見つかりません。TOC の PDF 生成をスキップします。')
              return
            end
            # TOC も post_process を適用して見出しメタを付与（PDFアウトライン用）
            Vivlio::Starter::ThorCLI.start(%w[post_process 03-toc])
            Common.log_info('[Step 6] 03-toc.html に post_process を適用しました（見出しメタ付与）')
            Vivlio::Starter::ThorCLI.start(%w[entries 03-toc])
            # 改良された pdf コマンドに出力ファイル名を渡してリネームも一括処理
            Vivlio::Starter::ThorCLI.start(['pdf', '03-toc.pdf'])
            Common.log_success('[Step 6] 03-toc.pdf を生成しました') if File.exist?('03-toc.pdf')
          end
        end
      end
    end
  end
end
