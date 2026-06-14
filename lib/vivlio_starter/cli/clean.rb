# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/clean.rb
# ================================================================
# 責務:
#   ビルド生成物・中間ファイル・キャッシュを安全にクリーンアップする。
#   最終成果物（output.pdf）は通常保持し、--purge で削除可能。
#
# 削除対象:
#   - .vivliostyle/: Vivliostyle CLI のワークディレクトリ
#   - *.html: Markdown から変換された HTML
#   - entries.js: 目次生成用の ES Module
#   - _toc.md, _titlepage.md 等: ビルド時に生成される特殊ページ
#   - 中間 PDF: _titlepage.pdf, _sections.pdf 等の作業用ファイル
#   - .cache/vs/: ビルドキャッシュ（--cache オプション）
#   - .cache/metrics/: metrics キャッシュ（--cache オプション）
#   - covers/: 生成されたカバー画像（--cover オプション、マスターは保持）
#
# 保持対象（--purge 未指定時）:
#   - 最終 PDF: output.pdf, output_compressed.pdf（config で名称変更可）
#   - ドキュメント: README.md, CHANGELOG.md 等
#
# 依存:
#   - Common: 設定読み込み・ログ出力・パス定数
#   - config/book.yml: カバー画像のファイル名設定
# ================================================================

require 'fileutils'

module VivlioStarter
  module CLI
    # ビルド生成物のクリーンアップコマンド
    #
    # オプション:
    #   - (なし): 中間生成物を削除、最終 PDF は保持
    #   - --purge: 最終 PDF も含めてすべて削除
    #   - --cache: キャッシュディレクトリのみ削除
    #   - --cover: 生成されたカバー画像のみ削除（マスターは保持）
    #   - --all: 上記すべてを実行（開発者向け）
    module CleanCommands
      module_function

      CLEAN_DESC = {
        short: '不要ファイルやキャッシュを削除します',
        long: <<~DESC
          生成物（HTML/中間PDF など）を削除する標準クリーンに加えて、
          各オプションで特定のファイルのみを削除できます。
          - `vs clean`            : 生成物（HTML / 中間PDF 等）を削除（最終PDFは保持）
          - `vs clean --purge`    : 最終PDFも含めてすべて削除
          - `vs clean --cache`    : キャッシュディレクトリのみ削除（生成物は保持）
          - `vs clean --cover`    : 生成されたカバー画像のみを削除（マスターは保持）
        DESC
      }.freeze

      # クリーンアップ処理のエントリーポイント
      #
      # @param option_hash [Hash] オプション設定
      #   - :all [Boolean] すべてのクリーンオプションを有効化
      #   - :cover [Boolean] カバー画像のみ削除
      #   - :cache [Boolean] キャッシュのみ削除
      #   - :purge [Boolean] 最終 PDF も含めて削除
      #   - :generated_images [Boolean] テーマバリアント画像を削除
      # @return [void]
      def execute_clean(option_hash)
        opts = option_hash || {}

        # --all は他のすべてのオプションを暗黙的に有効化する（--index-dictionaries は除く）
        all_mode = opts[:all]
        cover_requested = opts[:cover] || all_mode
        cache_requested = opts[:cache] || all_mode
        purge_requested = opts[:purge] || all_mode
        variant_cleanup_requested = opts[:generated_images] || all_mode
        index_dictionaries_requested = opts[:index_dictionaries] # --all には含めない

        # カバー画像の削除（マスター画像は保持）
        clean_cover_files if cover_requested
        # テーマ用の生成済みバリアント画像を削除
        clean_bundled_variant_images if variant_cleanup_requested
        # 索引・用語集辞書データの削除（確認あり）
        clean_index_dictionaries if index_dictionaries_requested

        if cache_requested
          begin
            dir = begin
              Common.cache_dir
            rescue StandardError
              '.cache/vs'
            end
            if dir.nil? || dir.to_s.strip.empty?
              Common.log_warn('キャッシュディレクトリが不明のため中止します')
              return
            end
            if File.directory?(dir)
              Common.log_action("キャッシュディレクトリを削除中: #{dir}")
              FileUtils.rm_rf(dir)
              Common.log_success('キャッシュ削除が完了しました')
            else
              Common.log_info("キャッシュディレクトリは存在しません: #{dir}")
            end

            # metrics キャッシュも削除
            metrics_cache = File.join('.cache', 'metrics')
            if File.directory?(metrics_cache)
              Common.log_action("metrics キャッシュを削除中: #{metrics_cache}")
              FileUtils.rm_rf(metrics_cache)
              Common.log_info("#{metrics_cache} を削除しました")
            end

            # 索引のキャッシュも削除
            index_cache = '_index_matches.yml'
            if File.exist?(index_cache)
              FileUtils.rm_f(index_cache)
              Common.log_info("#{index_cache} を削除しました")
            end

            # 索引ページもキャッシュ削除時に削除対象とする
            index_page = '_indexpage.html'
            if File.exist?(index_page)
              FileUtils.rm_f(index_page)
              Common.log_info("#{index_page} を削除しました")
            end

            if File.directory?('.vivliostyle')
              Common.log_action('.vivliostyle ディレクトリを削除中...')
              FileUtils.rm_rf('.vivliostyle')
              Common.log_info('.vivliostyle ディレクトリを削除しました')
            else
              Common.log_info('.vivliostyle ディレクトリは存在しません')
            end
          rescue StandardError => e
            Common.log_warn("clean --cache 実行中にエラー: #{e}")
          end
        end

        # --cache または --cover のみが指定された場合は通常のクリーン処理をスキップ
        # --purge が指定されている、またはオプションなしの場合は通常のクリーン処理を実行
        if (cache_requested || cover_requested) && !purge_requested
          # --cache または --cover のみの場合はここで終了
          return
        end

        # BuildHelpers.clean_generated_files! と等価の処理をここに実装
        Common.log_action('.vivliostyle ディレクトリを削除中...')
        FileUtils.rm_rf('.vivliostyle')

        Common.log_action('生成ファイルを削除中...')
        cleanup_patterns = [
          # HTML/JS 中間生成物
          '*.html',
          'entries.js',
          # 生成される一時/補助的な Markdown（任意）
          '_toc.md',
          # pre_process によりプロジェクトルートへ展開される章系の Markdown のみ削除対象に限定
          # 例: 11-install.md など（任意の *.md やドキュメントは削除しない）
          '[0-9][0-9]-*.md',
          # 内部 basename 方式の特殊ページ
          '_titlepage.md', '_legalpage.md', '_colophon.md', '_indexpage.html',
          '_index_matches.yml', '_index_review.md', '_index_glossary_review.md',
          # 中扉（Part Title Page）
          '_part*.md',
          # EPUB 中間ファイル
          'vivliostyle.config.epub.js',
          'entries.epub.js'
        ]

        intermediate_pdfs = [
          # 内部名ベースの中間PDF
          '_titlepage.pdf', '_legalpage.pdf', '_colophon.pdf',
          '_titlepage_legalpage.pdf', '_sections.pdf',
          '00-preface.pdf', '_toc.pdf',
          'blank_page.pdf', 'blank_frontmatter_insert.pdf',
          'output_tmp*.pdf',
          # 入稿用 PDF の中間ファイル（Step 13）
          '_titlepage_legalpage_print.pdf', '_sections_print.pdf',
          '_colophon_print.pdf', '_blank_before_colophon.pdf',
          'output_print.pdf'
        ]
        cleanup_patterns.concat(intermediate_pdfs)

        final_pdfs = [
          Common::CONFIG.dig('pdf', 'output_file') || 'output.pdf',
          Common::CONFIG.dig('pdf', 'output_file_compressed') || 'output_compressed.pdf'
        ].uniq

        # --purge 指定時は最終PDFも削除対象に含める
        if purge_requested
          cleanup_patterns.concat(final_pdfs)
          # 単章PDF（例: 11-install.pdf, 81-install.pdf など）も削除
          # 既に個別に列挙している中間PDFと重複しても問題ない
          cleanup_patterns << '[0-9][0-9]-*.pdf'
          # 単章EPUB（例: 01-life.epub, 02-history.epub など）も削除
          cleanup_patterns << '[0-9][0-9]-*.epub'
          # 動的ファイル名のPDFおよびEPUBも削除対象に追加
          add_dynamic_filename_patterns(cleanup_patterns)
        end

        cleanup_patterns.each do |pattern|
          Dir.glob(pattern).each do |file|
            next if File.directory?(file)

            FileUtils.rm_f(file)
            Common.log_info("#{file} を削除しました")
          end
        end
        Common.log_success('不要ファイルの削除が完了しました')
      end

      # config/book.yml の project.name から動的ファイル名パターンを生成し追加する
      #
      # @param patterns [Array<String>] 削除対象パターンリスト（破壊的に追加）
      # @return [void]
      #
      # 生成されるパターン例（project.name が "vivlio_starter" の場合）:
      #   - vivlio_starter*.pdf
      #   - vivlio_starter_v*.pdf（バージョン付き）
      #   - vivlio_starter_print*.pdf（印刷用）
      def add_dynamic_filename_patterns(patterns)
        config = Common::CONFIG
        project_name = config.dig('project', 'name')
        return unless project_name

        patterns << "#{project_name}*.pdf"
        patterns << "#{project_name}_v*.pdf"
        patterns << "#{project_name}_print*.pdf"
        patterns << "#{project_name}*.epub"
        patterns << "#{project_name}_v*.epub"
      end

      # bundled テーマ用に生成されたバリアント画像を削除する
      #
      # @return [void]
      #
      # 削除対象: stylesheets/images/bundled/ 内の *_portrait.webp, *_landscape.webp
      # これらはビルド時に自動生成される派生画像であり、再生成可能
      def clean_bundled_variant_images
        images_dir = File.join(Common::STYLESHEETS_DIR, 'images', 'bundled')
        unless Dir.exist?(images_dir)
          Common.log_info("bundled テーマ画像ディレクトリが存在しません: #{images_dir}")
          return
        end

        Common.log_action('bundled テーマバリアント画像を削除中...')
        # 最終バリアント（*_portrait/*_landscape）に加え、生成途中の中間ファイル
        # （*_alpha* / *_color* / *_merged*、png/webp 双方）も保険として掃除対象に含める。
        # 元画像（sakura.webp 等）には一致しないパターンに限定する。
        patterns = %w[
          *_portrait.webp *_landscape.webp
          *_alpha*.webp *_color*.webp *_merged*.webp
          *_alpha*.png *_color*.png *_merged*.png
        ]
        deleted = 0

        patterns.each do |pattern|
          Dir.glob(File.join(images_dir, pattern)).each do |file|
            next unless File.file?(file)

            FileUtils.rm_f(file)
            Common.log_info("#{file} を削除しました")
            deleted += 1
          end
        end

        if deleted.zero?
          Common.log_info('削除対象の bundled バリアント画像はありませんでした')
        else
          Common.log_success("bundled テーマバリアントを削除しました（#{deleted}ファイル）")
        end
      rescue StandardError => e
        Common.log_warn("bundled テーマバリアント削除中にエラー: #{e.message}")
      end

      # 索引・用語集辞書データを削除する（確認プロンプトあり）
      #
      # @return [void]
      #
      # 削除対象:
      #   - config/index_glossary_terms.yml（登録済み用語）
      #   - config/index_glossary_rejected.yml（除外用語）
      def clean_index_dictionaries
        targets = [
          File.join('config', 'index_glossary_terms.yml'),
          File.join('config', 'index_glossary_rejected.yml')
        ].select { |f| File.exist?(f) }

        if targets.empty?
          Common.log_info('削除対象の索引辞書ファイルはありませんでした')
          return
        end

        Common.log_warn('以下の索引・用語集辞書データを削除しようとしています:')
        targets.each { |f| Common.log_always("  - #{f}") }
        Common.log_always('これらのファイルには著者が登録した用語データが含まれています。')
        $stdout.print('本当に削除しますか？ [y/N]: ')
        ans = $stdin.gets
        unless ans && ans.strip.downcase == 'y'
          Common.log_info('索引辞書データの削除をキャンセルしました')
          return
        end

        targets.each do |f|
          FileUtils.rm_f(f)
          Common.log_success("削除しました: #{f}")
        end
      end

      # 生成されたカバー画像を削除する（マスター画像・ユーザーSVGは保持）
      #
      # @return [void]
      #
      # 削除対象:
      #   - covers/ 内の *.pdf, *.jpg（coverコマンドで生成されたファイル）
      #   - covers/ 内の *_light.svg, *_dark.svg（bundledテンプレートから生成されたSVG）
      #   - covers/ 内の *_rendered.svg（ユーザーSVGにプレースホルダー適用した中間ファイル）
      #
      # 保持対象:
      #   - *.png（frontcover_master.png 等、利用者が用意した画像）
      #   - *.key（Keynote ソースファイル）
      #   - covers/bundled/ 内のファイル（テンプレート本体）
      #   - light/dark 以外の *.svg（frontcover_floral.svg 等、利用者が用意したSVG）
      def clean_cover_files
        config = Common.load_config
        covers_dir = config.dig(:directories, :covers) || Common::COVERS_DIR

        unless File.directory?(covers_dir)
          Common.log_info("カバーディレクトリが存在しません: #{covers_dir}")
          return
        end

        Common.log_action('生成されたカバー画像を削除中...')

        deleted_count = 0

        # PDF / JPG はすべて生成物として削除
        %w[*.pdf *.jpg].each do |pattern|
          Dir.glob(File.join(covers_dir, pattern)).each do |file_path|
            next unless File.file?(file_path)

            FileUtils.rm_f(file_path)
            Common.log_info("  削除: #{File.basename(file_path)}")
            deleted_count += 1
          end
        end

        # SVG は bundled テンプレートから生成されたもの（light/dark）と
        # プレースホルダー適用済み中間ファイル（*_rendered.svg）のみ削除
        # 利用者が用意した SVG（floral.svg 等）は保持する
        bundled_themes = %w[light dark]
        Dir.glob(File.join(covers_dir, '*.svg')).each do |file_path|
          next unless File.file?(file_path)

          basename = File.basename(file_path, '.svg') # 例: frontcover_dark
          # *_light.svg / *_dark.svg → bundled テンプレートからの生成物
          is_bundled_generated = bundled_themes.any? { |t| basename.end_with?("_#{t}") }
          # *_rendered.svg → apply_text_placeholders_to_svg の中間ファイル
          is_rendered = basename.end_with?('_rendered')

          next unless is_bundled_generated || is_rendered

          FileUtils.rm_f(file_path)
          Common.log_info("  削除: #{File.basename(file_path)}")
          deleted_count += 1
        end

        if deleted_count.zero?
          Common.log_info('削除対象のカバー画像はありませんでした')
        else
          Common.log_success("カバー画像を削除しました（#{deleted_count}ファイル）")
        end
      end
    end
  end
end
