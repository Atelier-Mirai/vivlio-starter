# frozen_string_literal: true

require 'fileutils'
require_relative '../cover'

module VivlioStarter
  module CLI
    module Build
      module PdfMerger
        module_function

        # ================================================================
        # 1. 結合対象ファイルのリスト作成
        # ================================================================
        def cover_enhanced_files
          files = %w[_titlepage_legalpage.pdf _sections.pdf _colophon.pdf]
          cfg = Common::CONFIG

          # ターゲット判定（dig で安全アクセス）
          targets = extract_targets(cfg.dig(:output, :targets))
          targets = extract_targets(cfg.dig(:output, :pdf, :targets)) if targets.empty?
          pdf_selected = targets.empty? || targets.any? { it.include?('pdf') }

          return files.compact unless pdf_selected

          # 新しいカバー設定の取得
          return files.compact unless Common.pdf_combined?

          begin
            page_use   = resolve_page_use(cfg.page)
            covers_dir = cfg.directories&.covers || 'covers'

            ensure_cover_assets_for_page_size!(page_use)

            # テーマに応じたカバーを生成
            theme = Common.cover_theme
            size = extract_size_from_preset(page_use)

            # パス生成
            front = File.join(covers_dir, "frontcover_#{theme}_#{size}_rgb.pdf")
            back  = File.join(covers_dir, "backcover_#{theme}_#{size}_rgb.pdf")

            files.unshift(front) if File.exist?(front)
            files.push(back)     if File.exist?(back)
          rescue StandardError => e
            Common.log_warn("[Step 10] カバー結合設定の処理中にエラー: #{e.message}")
          end

          files.compact
        end

        # ================================================================
        # 2. 補助メソッド (Data / Pattern Matching 活用)
        # ================================================================

        def extract_targets(raw)
          case raw
          in String => s then s.split(',').map(&:strip).reject(&:empty?)
          in Array  => a then a.map(&:to_s).map(&:strip).reject(&:empty?)
          else []
          end
        end

        def resolve_page_use(page_cfg)
          # Data オブジェクトからプリセット名を優先順位付きで取得
          %i[use preset preset_name size].each do |key|
            val = page_cfg&.[](key)
            return val.to_s if val && !val.to_s.strip.empty?
          end
          'b5_standard'
        end

        def extract_size_from_preset(preset_name)
          case preset_name.to_s
          when /a4/ then 'a4'
          when /a5/ then 'a5'
          when /b5/ then 'b5'
          else 'a4' # デフォルト
          end
        end

        # ================================================================
        # 3. カバー自動生成ロジック
        # ================================================================
        def ensure_cover_assets_for_page_size!(page_use)
          size = CoverCommands.detect_page_size(page_use)
          return if cover_generation_attempts[size]

          cover_generation_attempts[size] = true
          Common.log_action('[Step 10] カバー画像を自動生成します…')

          CoverCommands.ensure_cover_files_for_build!
          Common.log_info('[Step 10] カバー画像の生成を完了しました')
        rescue StandardError => e
          Common.log_warn("[Step 10] カバー生成中にエラー: #{e.message}")
        end

        def cover_generation_attempts
          @cover_generation_attempts ||= {}
        end

        # ================================================================
        # 4. PDF 結合実行 (Step 10)
        # ================================================================
        def merge_all_pdfs!(_entries_or_keep = nil)
          Common.log_action('[Step 10] 表紙、本文、奥付を結合します…')

          files          = cover_enhanced_files
          existing_files = files.select { File.exist?(it) }

          if existing_files.empty?
            Common.log_error('[Step 10] 結合対象PDFがありません')
            return false
          end

          return false unless qpdf_available?

          # 奥付を偶数ページ（左ページ）に配置するため、必要なら空白ページを挿入
          existing_files = insert_blank_page_before_colophon(existing_files)

          # _sections.pdf があればそれをベースに、なければ最初のファイルを使用
          base_pdf = existing_files.include?('_sections.pdf') ? '_sections.pdf' : existing_files.first
          FileUtils.rm_f('output.pdf')

          # 引数構築
          ranges = existing_files.map { %("#{it}" 1-z) }.join(' ')
          success = system(%(qpdf "#{base_pdf}" --pages #{ranges} -- "output.pdf" > /dev/null))

          if success && File.exist?('output.pdf')
            Common.log_success('[Step 10] output.pdf を生成しました')
            true
          else
            Common.log_error('[Step 10] PDF結合に失敗しました')
            false
          end
        end

        # 奥付が偶数ページ（左ページ）始まりになるよう空白ページを挿入
        # _colophon.pdf（閲覧用）と _colophon_print.pdf（入稿用）の両方に対応
        def insert_blank_page_before_colophon(files)
          colophon_idx = files.index { it.include?('_colophon') }
          return files unless colophon_idx

          preceding = files[0...colophon_idx]

          # カバーPDFはページ番号体系に含まれないため parity 計算から除外
          body_files = preceding.grep_v(%r{covers/})

          # 各PDFのページ数を個別に取得してログ出力（デバッグ時のみ）
          page_counts = body_files.map { |f| [f, Build::Utilities.page_count(f).to_i] }
          page_counts.each { |f, c| Common.log_debug("[Step 10] ページ数: #{f} = #{c}p") }
          total = page_counts.sum(&:last)
          Common.log_debug("[Step 10] 奥付前の合計ページ数（カバー除外）: #{total}")

          if total.zero?
            Common.log_debug('[Step 10] 奥付より前のPDFページ数を取得できませんでした')
            return files
          end

          # total が偶数 → 次ページは奇数（右） → 空白ページを挿入して偶数に
          # total が奇数 → 次ページは偶数（左） → そのままでOK
          if total.even?
            blank = Build::Utilities.ensure_blank_page_pdf('_blank_before_colophon.pdf')
            Common.log_debug("[Step 10] 奥付を偶数ページに配置するため空白ページを挿入します（前方 #{total} ページ）")
            files.dup.insert(colophon_idx, blank)
          else
            Common.log_debug("[Step 10] 奥付は偶数ページに配置されます（前方 #{total} ページ、空白挿入なし）")
            files
          end
        end

        def qpdf_available?
          return true if system('command -v qpdf >/dev/null 2>&1')

          Common.log_warn('[Step 10] qpdf が見つかりません。')
          false
        end

        # ================================================================
        # 5. アウトライン付与 (Step 11)
        # ================================================================
        def add_outline_to_output_pdf!(entries_or_keep = nil)
          return false unless File.exist?('output.pdf')

          keep_numbers = Build::Utilities.chapter_numbers_for_outline(entries_or_keep)

          # 抽出対象HTMLの絞り込み
          special_pages = %w[_toc]
          special_pages.push('_glossarypage', '_indexpage') if IndexCommands.index_enabled?

          chapter_htmls = Dir.glob('*.html').select do |path|
            bn = File.basename(path, '.html')
            num = bn[/\A(\d+)-/, 1]&.to_i

            (num && (keep_numbers.nil? || keep_numbers.include?(num))) ||
              special_pages.include?(bn)
          end

          if chapter_htmls.empty?
            Common.log_info('[Step 11] 本文HTMLなし。スキップします')
            return false
          end

          Common.log_action('[Step 11] PDF ブックマークを付与します…')
          OutlineExtractor.add_outline_from_headings!('output.pdf', chapter_htmls, max_level: 3, start_page: 1)
          true
        end
      end
    end
  end
end
