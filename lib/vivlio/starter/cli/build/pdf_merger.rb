# frozen_string_literal: true

require 'fileutils'
require_relative '../cover'

module Vivlio
  module Starter
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

            # ターゲット判定 (Dataオブジェクトでも [] アクセス可能に実装済み)
            targets = extract_targets(cfg.output&.targets)
            targets = extract_targets(cfg.output&.pdf&.targets) if targets.empty?
            pdf_selected = targets.empty? || targets.any? { _1.include?('pdf') }

            return files.compact unless pdf_selected

            # カバー設定の取得 (Dataオブジェクトなので nil-safe なドットアクセス)
            cover_cfg = cfg.output&.pdf&.cover
            return files.compact unless cover_cfg&.enabled != false

            begin
              page_use   = resolve_page_use(cfg.page)
              covers_dir = cfg.directories&.covers || 'covers'
              
              ensure_cover_assets_for_page_size!(page_use)

              # パス生成
              front = cover_cfg.front&.then { File.join(covers_dir, _1) }
              back  = cover_cfg.back&.then  { File.join(covers_dir, _1) }

              files.unshift(front) if front && File.exist?(front)
              files.push(back)     if back && File.exist?(back)
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

          # ================================================================
          # 3. カバー自動生成ロジック
          # ================================================================
          def ensure_cover_assets_for_page_size!(page_use)
            size = CoverCommands.detect_page_size(page_use)
            return if cover_generation_attempts[size]

            cover_generation_attempts[size] = true
            Common.log_action("[Step 10] `vs cover #{size}` を自動実行します…")
            
            CoverCommands.execute_for_size(size, nil)
            Common.log_info("[Step 10] `vs cover #{size}` の実行を完了しました")
          rescue StandardError => e
            Common.log_warn("[Step 10] vs cover #{size.upcase} 実行中にエラー: #{e.message}")
          end

          def cover_generation_attempts
            @cover_generation_attempts ||= {}
          end

          # ================================================================
          # 4. PDF 結合実行 (Step 10)
          # ================================================================
          def merge_all_pdfs!(entries_or_keep = nil)
            Common.log_action('[Step 10] 表紙、本文、奥付を結合します…')
            
            files          = cover_enhanced_files
            existing_files = files.select { File.exist?(_1) }
            
            if existing_files.empty?
              Common.log_error('[Step 10] 結合対象PDFがありません')
              return false
            end

            return false unless qpdf_available?

            # _sections.pdf があればそれをベースに、なければ最初のファイルを使用
            base_pdf = existing_files.include?('_sections.pdf') ? '_sections.pdf' : existing_files.first
            FileUtils.rm_f('output.pdf')
            
            # 引数構築
            ranges = existing_files.map { %("#{_1}" 1-z) }.join(' ')
            success = system(%(qpdf "#{base_pdf}" --pages #{ranges} -- "output.pdf" > /dev/null))

            if success && File.exist?('output.pdf')
              Common.log_success('[Step 10] output.pdf を生成しました')
              true
            else
              Common.log_error('[Step 10] PDF結合に失敗しました')
              false
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
            chapter_htmls = Dir.glob('*.html').sort.select do |path|
              bn = File.basename(path, '.html')
              num = bn[/\A(\d+)-/, 1]&.to_i
              
              (num && (keep_numbers.nil? || keep_numbers.include?(num))) || 
                %w[_toc _indexpage].include?(bn)
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
end