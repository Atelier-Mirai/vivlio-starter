# frozen_string_literal: true

require 'fileutils'
require_relative '../cover'
require_relative '../pre_process/book_settings_css'

module VivlioStarter
  module CLI
    module Build
      module PdfMerger
        # 結合順に並ぶ 1 区間。qpdf の `--pages` へ「ファイル＋ページ範囲」を渡す単位で、
        # 従来の「ファイルの列」は range が全ページの特別な場合にすぎない。
        #
        # role を持たせているのは、奥付前の白紙判定とアウトライン基点の算出を
        # **パスの綴りに依存させない**ため。前付・奥付が本文 PDF に相乗りすると
        # 3 区間すべてが同じ `_sections.pdf` を指し、ファイル名では区別できなくなる。
        #
        # @!attribute role [Symbol] :cover_front / :front_matter / :body / :blank / :colophon / :cover_back
        # @!attribute range [String] qpdf のページ範囲（'1-z' でファイル全体）
        Segment = Data.define(:role, :path, :range, :pages)

        module_function

        # ================================================================
        # 1. 結合対象リストの作成
        # ================================================================

        # 結合順の区間列。前付・奥付が本文 PDF に相乗りしていれば同じファイルの
        # 別範囲として、していなければ個別ファイルとして並べる。どちらも同じ
        # Segment の列になるので、以降の工程は区別しなくてよい。
        def cover_enhanced_segments
          segments = body_and_matter_segments
          cfg = Common::CONFIG

          # ターゲット判定
          targets = extract_targets(cfg.output.targets)
          pdf_selected = targets.empty? || targets.any? { it.include?('pdf') }

          return segments unless pdf_selected
          return segments unless Common.pdf_combined?

          begin
            page_use = resolve_page_use(cfg.page)

            ensure_cover_assets_for_page_size!(page_use)

            # テーマに応じたカバーを生成
            theme = Common.cover_theme
            size = extract_size_from_preset(page_use)

            # パス生成（生成物は cover_cache_dir に出ている）
            front = File.join(Common.cover_cache_dir, "frontcover_#{theme}_#{size}_rgb.pdf")
            back  = File.join(Common.cover_cache_dir, "backcover_#{theme}_#{size}_rgb.pdf")

            segments.unshift(whole_file_segment(:cover_front, front)) if File.exist?(front)
            segments.push(whole_file_segment(:cover_back, back))      if File.exist?(back)
          rescue StandardError => e
            Common.log_warn("[Step 10] カバー結合設定の処理中にエラー: #{e.message}")
          end

          segments
        end

        # 本文・前付・奥付の 3 区間。中間 PDF はワークスペース pdf/ 内に置かれる。
        #
        # 相乗り経路では 1 本の `_sections.pdf` から 3 範囲を切り出す。分割して
        # 別ファイルにすると各ファイルがフォントを丸ごと抱え込み、実測で最終 PDF が
        # 約 1.9MB 太る（front-back-matter-single-render-spec.md §3.1）。
        def body_and_matter_segments
          sections = File.join(Common::BUILD_PDF_DIR, '_sections.pdf')
          ranges = Build::PdfBuilder.embedded_special_page_ranges(sections)

          return embedded_segments(sections, ranges) if ranges

          separate_segments(front_matter: '_titlepage_legalpage.pdf', body: '_sections.pdf',
                            colophon: '_colophon.pdf')
        end

        # 1 本の PDF に相乗りした前付・奥付を 3 区間へ割る（閲覧用・入稿用で共用）
        def embedded_segments(path, ranges)
          [
            ranged_segment(:front_matter, path, ranges[:front]),
            ranged_segment(:body,         path, ranges[:body]),
            ranged_segment(:colophon,     path, ranges[:colophon])
          ]
        end

        # 前付・奥付を個別レンダしたときの 3 区間（フォールバック経路・閲覧用と入稿用で
        # ファイル名が違うため basename を受け取る）
        def separate_segments(front_matter:, body:, colophon:)
          { front_matter:, body:, colophon: }.map do |role, name|
            whole_file_segment(role, File.join(Common::BUILD_PDF_DIR, name))
          end
        end

        # ファイル全体を 1 区間として扱う
        def whole_file_segment(role, path)
          Segment.new(role:, path:, range: '1-z', pages: Build::Utilities.page_count(path).to_i)
        end

        # ページ範囲を 1 区間として扱う
        def ranged_segment(role, path, range)
          Segment.new(role:, path:, range: "#{range.first}-#{range.last}", pages: range.size)
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

          segments = cover_enhanced_segments.select { File.exist?(it.path) }

          if segments.empty?
            Common.log_error('[Step 10] 結合対象PDFがありません')
            return false
          end

          return false unless qpdf_available?

          # 奥付を偶数ページ（左ページ）に配置するため、必要なら空白ページを挿入
          segments = insert_blank_page_before_colophon(segments)

          # アウトライン付与の基点補正用に、前付より前に結合される表紙 PDF の
          # ページ数を記録しておく（Step 11 で参照）。
          @front_matter_offset = compute_front_matter_offset(segments)

          if merge_pdfs_with_qpdf!(segments, output: merged_output_pdf, base_pdf: base_pdf_for(segments))
            Common.log_success('[Step 10] output.pdf を生成しました')
            true
          else
            Common.log_error('[Step 10] PDF結合に失敗しました')
            false
          end
        end

        # メタデータ・しおりの引き継ぎ元。本文を優先する（ベース PDF の情報が
        # 出力へ受け継がれるため、表紙 1 枚の情報で上書きされないようにする）。
        def base_pdf_for(segments)
          segments.find { it.role == :body }&.path || segments.first.path
        end

        # 結合済み PDF のパス（ワークスペース pdf/ 内。最終リネームでルートへ出る）
        def merged_output_pdf = File.join(Common::BUILD_PDF_DIR, 'output.pdf')

        # 区間列を qpdf で 1 本の PDF に結合する（閲覧用・入稿用ビルドの共通基盤）。
        #
        # base_pdf を「結合のベース」として qpdf に渡すと、その PDF の
        # メタデータが出力へ引き継がれる。指定がなければ先頭区間のファイルを使う。
        #
        # 同じファイルが複数区間に現れてよい（相乗り経路では 3 区間が同一ファイル）。
        # qpdf は入力ごとに 1 度だけ読み込むため、フォントなどの共有資源は重複しない。
        #
        # @param segments [Array<Segment>] 結合順の区間（存在確認済みであること）
        # @param output [String] 出力 PDF パス（既存ファイルは上書き）
        # @param base_pdf [String, nil] メタデータ引き継ぎ元の PDF
        # @return [Boolean] 結合に成功し出力ファイルが存在すれば true
        def merge_pdfs_with_qpdf!(segments, output:, base_pdf: nil)
          return false if segments.empty?

          base_pdf ||= segments.first.path
          FileUtils.rm_f(output)

          pages = segments.map { %("#{it.path}" #{it.range}) }.join(' ')
          success = system(%(qpdf "#{base_pdf}" --pages #{pages} -- "#{output}" > /dev/null))
          success && File.exist?(output)
        end

        # 奥付が偶数ページ（左ページ）始まりになるよう空白ページを挿入する。
        # 閲覧用・入稿用のどちらの区間列にも使う。
        #
        # page.chapter_pagebreak: any（面を問わない）では挿入しない。奥付を左ページに
        # 置くのは改丁とは別の慣習だが、「どちら側でもよい」と宣言した本で白紙だけが
        # 残るのは一貫しない（chapter-pagebreak-spec.md §2.3）。
        #
        # @param segments [Array<Segment>]
        # @return [Array<Segment>]
        def insert_blank_page_before_colophon(segments)
          if chapter_pagebreak_any?
            Common.log_debug('[Step 10] page.chapter_pagebreak: any のため奥付前の空白ページを挿入しません')
            return segments
          end

          colophon_idx = segments.index { it.role == :colophon }
          return segments unless colophon_idx

          # カバーはページ番号体系に含まれないため parity 計算から除外
          preceding = segments[0...colophon_idx].reject { it.role == :cover_front }
          preceding.each { Common.log_debug("[Step 10] ページ数: #{it.path} #{it.range} = #{it.pages}p") }
          total = preceding.sum(&:pages)
          Common.log_debug("[Step 10] 奥付前の合計ページ数（カバー除外）: #{total}")

          if total.zero?
            Common.log_debug('[Step 10] 奥付より前のPDFページ数を取得できませんでした')
            return segments
          end

          # total が偶数 → 次ページは奇数（右） → 空白ページを挿入して偶数に
          # total が奇数 → 次ページは偶数（左） → そのままでOK
          if total.even?
            blank = Build::Utilities.ensure_blank_page_pdf(File.join(Common::BUILD_PDF_DIR, '_blank_before_colophon.pdf'))
            Common.log_debug("[Step 10] 奥付を偶数ページに配置するため空白ページを挿入します（前方 #{total} ページ）")
            segments.dup.insert(colophon_idx, Segment.new(role: :blank, path: blank, range: '1-z', pages: 1))
          else
            Common.log_debug("[Step 10] 奥付は偶数ページに配置されます（前方 #{total} ページ、空白挿入なし）")
            segments
          end
        end

        # 値の正規化と不正値の警告は BookSettingsCss が唯一の実装。ここは判定だけ借りる。
        def chapter_pagebreak_any?
          return false unless Common.configured?

          PreProcessCommands::BookSettingsCss
            .chapter_pagebreak_value(Common::CONFIG.page) == 'any'
        rescue StandardError
          false
        end

        def qpdf_available?
          return true if system('command -v qpdf >/dev/null 2>&1')

          Common.log_warn('[Step 10] qpdf が見つかりません。')
          false
        end

        # output.pdf 先頭に結合される表紙 PDF など、前付より前に並ぶページ数を返す。
        # アウトラインのページ位置計算の基点（本扉の実ページ番号 = offset + 1）を
        # 補正するために用いる。merge_all_pdfs! 実行時に算出される。
        # 未算出時は 0（表紙なし相当）。
        def front_matter_offset = @front_matter_offset || 0

        # 区間列のうち、前付より前のページ数を合算する。
        # 前付が見つからない場合は 0 を返す（従来挙動と互換）。
        def compute_front_matter_offset(segments)
          idx = segments.index { it.role == :front_matter }
          return 0 unless idx

          segments[0...idx].sum(&:pages)
        end

        # ================================================================
        # 5. アウトライン付与 (Step 11)
        # ================================================================
        def add_outline_to_output_pdf!(entries_or_keep = nil)
          return false unless File.exist?(merged_output_pdf)

          keep_numbers = Build::Utilities.chapter_numbers_for_outline(entries_or_keep)

          # 抽出対象HTMLの絞り込み（dedup 済み HTML はワークスペース pdf/ 内・P4 §5.1）
          special_pages = %w[_toc]
          special_pages.push('_glossarypage', '_indexpage') if IndexCommands.index_enabled?

          chapter_htmls = Dir.glob(File.join(Common::BUILD_PDF_DIR, '*.html')).select do |path|
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
          # 表紙 PDF のページ数を基点に加味して、前付・本文・巻末のページ範囲を正しく算出する。
          OutlineExtractor.add_outline_from_headings!(merged_output_pdf, chapter_htmls, max_level: 3,
                                                                                        start_page: front_matter_offset + 1)
          true
        end
      end
    end
  end
end
