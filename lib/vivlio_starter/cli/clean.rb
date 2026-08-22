# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/clean.rb
# ================================================================
# 責務:
#   ビルド生成物・中間ファイル・キャッシュを安全にクリーンアップする。
#   最終成果物（output.pdf）は通常保持し、--purge で削除可能。
#
# 削除対象:
#   - .cache/vs/build/: ビルドワークスペース（P4: 現行パイプラインの中間物はここに閉じる）
#   - .vivliostyle/: Vivliostyle CLI のワークディレクトリ（旧バージョンの残骸）
#   - _index_review.md 等: vs index:auto が著者レビュー用にルートへ出す作業ファイル
#   - ルートの *.html / 章 .md / 中間 PDF / entries.js 等: 旧バージョン（P4 以前・
#     撤去済み手動フロー）の残骸掃除（LEGACY_* パターン・1 リリース残して V2.0 で撤去予定）
#   - .cache/vs/: ビルドキャッシュ（--cache オプション）
#   - .cache/metrics/: metrics キャッシュ（--cache オプション）
#   - .cache/vs/covers/: 生成されたカバー画像（--cover オプション。covers/ は
#     著者マスターのみになったため触れない。旧配置の残骸掃除だけ 1 リリース残す）
#
# 保持対象（--purge 未指定時）:
#   - 最終 PDF: output.pdf, output_compressed.pdf（config で名称変更可）
#   - 最終 EPUB / Kindle: <project>*.epub, <project>*.kpf
#   - ドキュメント: README.md, CHANGELOG.md 等
#
# --purge 指定時は上記の最終 PDF / EPUB / KPF も含めてすべて削除する。
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
    #   - (なし): 中間生成物を削除、最終 PDF / EPUB / KPF は保持
    #   - --purge: 最終 PDF / EPUB / KPF も含めてすべて削除
    #   - --cache: キャッシュディレクトリのみ削除
    #   - --cover: 生成されたカバー画像のみ削除（マスターは保持）
    #   - --all: 上記すべてを実行（開発者向け）
    module CleanCommands
      module_function

      # 索引レビューファイル。`vs index:auto` が書き出すが、そこから先は
      # **著者が編集する入力**であって中間生成物ではない。ビルドのたびに消すと、
      # 「除外済みリストから戻す語を選ぶ」ような途中の判断がまるごと失われ、
      # `vs index:apply` は「ファイルが見つかりません」で終わる。
      # 掃除するのは意図が明示された `--purge` のときだけにする。
      # （_index_matches.yml は P4b で workspace 化、entries.js は手動フロー撤去で
      #  いずれも LEGACY_ROOT_PATTERNS へ移動）
      REVIEW_FILE_PATTERNS = %w[
        _index_review.md _index_glossary_review.md
      ].freeze

      # ------------------------------------------------------------
      # 旧バージョン残骸掃除（legacy・V2.0 で撤去予定）
      # ------------------------------------------------------------
      # P4（ワークスペース分離）以前のビルドは中間 md/HTML/中間 PDF を
      # プロジェクトルートへ生成していた。現行パイプラインの中間物は
      # .cache/vs/build/ に閉じており、以下のパターンに該当するルート生成は
      # もう起きない。旧バージョンからの移行者のために 1 リリースだけ残す
      # （P4 §3.4-8）。

      # HTML / 章 Markdown / 特殊ページ / EPUB 補助ファイルの残骸パターン
      LEGACY_ROOT_PATTERNS = [
        # Markdown から変換されたルート HTML（_indexpage.html 等の特殊ページ HTML を含む）
        '*.html',
        # 生成される一時/補助的な Markdown
        '_toc.md',
        # pre_process がルートへ展開していた章 Markdown のみ削除対象に限定
        # 例: 11-install.md など（任意の *.md やドキュメントは削除しない）
        '[0-9][0-9]-*.md',
        # 内部 basename 方式の特殊ページ
        '_titlepage.md', '_legalpage.md', '_colophon.md',
        # 中扉（Part Title Page）
        '_part*.md',
        # EPUB 中間ファイル（P4 段階 4 で epub/・kindle/ 内生成へ移行）
        'vivliostyle.config.epub.js',
        'entries.epub.js',
        # 旧手動フロー（vs entries → vs pdf・撤去済み）の生成物
        'entries.js',
        # EPUB 同梱用 book-settings.css 変種（正規の .cache/vs/ 版は --cache で掃除）
        'book-settings.css',
        # 索引スキャンのルート出力（P4b で workspace 直下へ移行・.cache/vs 側は --cache で掃除）
        '_index_matches.yml'
      ].freeze

      # ルートの中間 PDF の残骸パターン（P4 段階 3 で pdf/ 内生成へ移行）
      LEGACY_INTERMEDIATE_PDF_PATTERNS = [
        # 内部名ベースの中間PDF
        '_titlepage.pdf', '_legalpage.pdf', '_colophon.pdf',
        '_titlepage_legalpage.pdf', '_sections.pdf',
        # _toc.pdf は廃止済み（OutlineExtractor が注釈対象 PDF から直接算出）
        '_toc.pdf',
        'blank_page.pdf', 'blank_frontmatter_insert.pdf',
        'output_tmp*.pdf',
        # 入稿用 PDF の中間ファイル
        '_titlepage_legalpage_print.pdf', '_sections_print.pdf',
        '_colophon_print.pdf', '_blank_before_colophon.pdf',
        'output_print.pdf'
      ].freeze

      # 削除結果の内訳。表示は呼び出し側の責務とし、ドメイン層は件数を返すだけにする。
      # `vs build` の Step 0 も execute_clean を呼ぶため、ここで結果報告を出すと
      # ビルドのたびに「削除しました」が混ざってしまう。
      CleanSummary = Data.define(:cache, :cover, :generated_images, :artifacts, :dictionaries) do
        def total = cache + cover + generated_images + artifacts + dictionaries
        def none? = total.zero?
      end

      # クリーンアップ処理のエントリーポイント
      #
      # @param option_hash [Hash] オプション設定
      #   - :all [Boolean] すべてのクリーンオプションを有効化
      #   - :cover [Boolean] カバー画像のみ削除
      #   - :cache [Boolean] キャッシュのみ削除
      #   - :purge [Boolean] 最終 PDF も含めて削除
      #   - :generated_images [Boolean] テーマバリアント画像を削除
      # @return [CleanSummary] 削除した対象の内訳
      def execute_clean(option_hash)
        opts = option_hash || {}

        # --all は他のすべてのオプションを暗黙的に有効化する（--index-dictionaries は除く）
        all_mode = opts[:all]
        cover_requested = opts[:cover] || all_mode
        cache_requested = opts[:cache] || all_mode
        purge_requested = opts[:purge] || all_mode
        variant_cleanup_requested = opts[:generated_images] || all_mode
        index_dictionaries_requested = opts[:index_dictionaries] # --all には含めない

        cover = cover_requested ? clean_cover_files : 0
        generated_images = variant_cleanup_requested ? clean_bundled_variant_images : 0
        dictionaries = index_dictionaries_requested ? clean_index_dictionaries : 0
        cache = cache_requested ? clean_cache_files : 0

        # キャッシュディレクトリを特定できない異常時は後続の削除も行わない（従来の挙動）
        if cache.nil?
          return CleanSummary.new(cache: 0, cover: cover, generated_images: generated_images,
                                  artifacts: 0, dictionaries: dictionaries)
        end

        # --cache または --cover のみが指定された場合は通常のクリーン処理をスキップ。
        # --purge 指定時、またはオプションなしの場合は通常のクリーン処理を実行する
        artifacts = if (cache_requested || cover_requested) && !purge_requested
                      0
                    else
                      clean_build_artifacts(purge_requested)
                    end

        CleanSummary.new(cache: cache, cover: cover, generated_images: generated_images,
                         artifacts: artifacts, dictionaries: dictionaries)
      end

      # キャッシュ類（.cache/vs・metrics・索引の旧ルート残骸・.vivliostyle）を削除する
      #
      # @return [Integer, nil] 削除した対象の数。キャッシュディレクトリが特定できない場合は nil
      def clean_cache_files
        deleted = 0
        dir = begin
          Common.cache_dir
        rescue StandardError
          '.cache/vs'
        end

        if dir.nil? || dir.to_s.strip.empty?
          Common.log_warn('キャッシュディレクトリが不明のため中止します')
          return nil
        end

        if File.directory?(dir)
          Common.log_action("キャッシュディレクトリを削除中: #{dir}")
          FileUtils.rm_rf(dir)
          deleted += 1
          Common.log_success('キャッシュ削除が完了しました')
        else
          Common.log_info("キャッシュディレクトリは存在しません: #{dir}")
        end

        # metrics キャッシュも削除
        metrics_cache = File.join('.cache', 'metrics')
        if File.directory?(metrics_cache)
          Common.log_action("metrics キャッシュを削除中: #{metrics_cache}")
          FileUtils.rm_rf(metrics_cache)
          deleted += 1
          Common.log_info("#{metrics_cache} を削除しました")
        end

        # 索引のキャッシュ（旧ルート出力）も削除する。現行の新配置
        # .cache/vs/build/_index_matches.yml は上の rm_rf(dir) が掃除するため、
        # ここはルート残骸掃除として残置する（V2.0 で撤去予定・P4b §2.6）。
        index_cache = '_index_matches.yml'
        if File.exist?(index_cache)
          FileUtils.rm_f(index_cache)
          deleted += 1
          Common.log_info("#{index_cache} を削除しました")
        end

        # 索引ページもキャッシュ削除時に削除対象とする
        index_page = '_indexpage.html'
        if File.exist?(index_page)
          FileUtils.rm_f(index_page)
          deleted += 1
          Common.log_info("#{index_page} を削除しました")
        end

        if File.directory?('.vivliostyle')
          Common.log_action('.vivliostyle ディレクトリを削除中...')
          FileUtils.rm_rf('.vivliostyle')
          deleted += 1
          Common.log_info('.vivliostyle ディレクトリを削除しました')
        else
          Common.log_info('.vivliostyle ディレクトリは存在しません')
        end

        deleted
      rescue StandardError => e
        Common.log_warn("clean --cache 実行中にエラー: #{e}")
        deleted
      end

      # ビルドの中間生成物・成果物を削除する
      #
      # @param purge [Boolean] 最終 PDF / EPUB も削除対象に含めるか
      # @return [Integer] 削除した対象の数
      def clean_build_artifacts(purge)
        deleted = 0

        # 旧バージョンのビルド・撤去済み手動フロー（vs pdf）が残していた
        # Vivliostyle ワークディレクトリ。パイプラインの生成 config は workspaceDir を
        # ワークスペース内へ向けるためルートには生成しない（P4 §5.6・段階 5）。
        Common.log_action('.vivliostyle ディレクトリを削除中...')
        deleted += 1 if File.directory?('.vivliostyle')
        FileUtils.rm_rf('.vivliostyle')

        # ビルドワークスペース（P4: 現行パイプラインの中間物はすべてここに閉じる）を一括削除
        if File.directory?(Common::BUILD_DIR)
          FileUtils.rm_rf(Common::BUILD_DIR)
          deleted += 1
          Common.log_info("#{Common::BUILD_DIR} を削除しました")
        end

        Common.log_action('生成ファイルを削除中...')
        cleanup_patterns = LEGACY_ROOT_PATTERNS + LEGACY_INTERMEDIATE_PDF_PATTERNS

        final_pdfs = %w[output.pdf output_compressed.pdf]

        # --purge 指定時は最終PDFも削除対象に含める
        if purge
          cleanup_patterns.concat(final_pdfs)
          # 索引レビューファイルもここでだけ消す（既定のビルドでは残す）
          cleanup_patterns.concat(REVIEW_FILE_PATTERNS)
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
            deleted += 1
            Common.log_info("#{file} を削除しました")
          end
        end

        # ビルドが images/ 配下へ生成していた派生物の残骸を削除する。いずれも現行では
        # workspace / 消費者 dir 内生成へ移行済み。旧バージョン残骸掃除として 1 リリース残し
        # V2.0 で撤去する:
        #   - math: 数式 SVG（P4b で workspace html/images/ へ移行）
        #   - headings: 扉絵・節絵の合成画像（P4 段階 4 で消費者 dir 内へ）
        #   - _epub_assets: EPUB 用 WebP→JPEG 変換物（同上）
        %w[math headings _epub_assets].each do |subdir|
          legacy_dir = File.join(Common.images_dir, subdir)
          next unless File.directory?(legacy_dir)

          FileUtils.rm_rf(legacy_dir)
          deleted += 1
          Common.log_info("#{legacy_dir} を削除しました")
        end

        Common.log_success('不要ファイルの削除が完了しました')
        deleted
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
      #   - vivlio_starter*.epub（Kindle 中間 …-kindle.epub もここで拾う）
      #   - vivlio_starter*.kpf（Kindle 最終成果物）
      def add_dynamic_filename_patterns(patterns)
        project_name = Common::CONFIG.project.name
        return unless project_name

        patterns << "#{project_name}*.pdf"
        patterns << "#{project_name}_v*.pdf"
        patterns << "#{project_name}_print*.pdf"
        patterns << "#{project_name}*.epub"
        patterns << "#{project_name}_v*.epub"
        patterns << "#{project_name}*.kpf"
        patterns << "#{project_name}_v*.kpf"
      end

      # 生成されたテーマバリアント画像を削除する
      #
      # 正位置は生成キャッシュ .cache/vs/theme-images/（generated-assets 移設仕様 §2）。
      # 丸ごと削除して次ビルドで再生成させる。旧配置の残骸掃除も 1 リリースの間だけ行う（§6）。
      #
      # @return [Integer] 削除した対象の数
      def clean_bundled_variant_images
        deleted = 0
        cache_dir = Common.theme_images_cache_dir
        if Dir.exist?(cache_dir)
          FileUtils.rm_rf(cache_dir)
          deleted += 1
          Common.log_success("テーマバリアント画像キャッシュを削除しました: #{cache_dir}")
        else
          Common.log_info("テーマバリアント画像キャッシュは存在しません: #{cache_dir}")
        end

        deleted + clean_legacy_variant_images
      rescue StandardError => e
        Common.log_warn("テーマバリアント削除中にエラー: #{e.message}")
        deleted
      end

      # 旧配置（stylesheets/images/bundled/ 内）の生成バリアント残骸を掃除する。
      # generated-assets 移設前のプロジェクト向けの移行掃除（§6）。次のリリースで撤去する。
      #
      # @return [Integer] 削除した対象の数
      def clean_legacy_variant_images
        images_dir = File.join(Common::STYLESHEETS_DIR, 'images', 'bundled')
        return 0 unless Dir.exist?(images_dir)

        # 最終バリアント（*_portrait/*_landscape）に加え、生成途中の中間ファイル
        # （*_alpha* / *_color* / *_merged*、png/webp 双方）も保険として掃除対象に含める。
        # 元画像（sakura.webp 等）には一致しないパターンに限定する。
        patterns = %w[
          *_portrait.webp *_landscape.webp
          *_alpha*.webp *_color*.webp *_merged*.webp
          *_alpha*.png *_color*.png *_merged*.png
        ]
        deleted = patterns.sum do |pattern|
          Dir.glob(File.join(images_dir, pattern)).count do |file|
            next false unless File.file?(file)

            FileUtils.rm_f(file)
            Common.log_info("#{file} を削除しました")
            true
          end
        end

        Common.log_success("旧配置の生成バリアント画像を削除しました（.cache へ移設済み・#{deleted}ファイル）") if deleted.positive?
        deleted
      end

      # 索引・用語集辞書データを削除する（確認プロンプトあり）
      #
      # @return [Integer] 削除した対象の数（未実施・キャンセル時は 0）
      #
      # 削除対象:
      #   - config/index_glossary_terms.yml（登録済み用語）
      #   - config/index_glossary_rejected.yml（除外用語）
      #   - config/index_yomi_overrides.yml（読みの個人辞書）
      def clean_index_dictionaries
        targets = [
          File.join('config', 'index_glossary_terms.yml'),
          File.join('config', 'index_glossary_rejected.yml'),
          File.join('config', 'index_yomi_overrides.yml')
        ].select { |f| File.exist?(f) }

        if targets.empty?
          Common.log_info('削除対象の索引辞書ファイルはありませんでした')
          return 0
        end

        Common.log_warn('以下の索引・用語集辞書データを削除しようとしています:')
        targets.each { |f| Common.log_always("  - #{f}") }
        Common.log_always('これらのファイルには著者が登録した用語データが含まれています。')
        unless Common.confirm?('本当に削除しますか？')
          Common.log_info('索引辞書データの削除をキャンセルしました')
          return 0
        end

        targets.each do |f|
          FileUtils.rm_f(f)
          Common.log_success("削除しました: #{f}")
        end
        targets.size
      end

      # 生成されたカバー画像を削除する
      #
      # 正位置は生成キャッシュ .cache/vs/covers/（generated-assets 移設仕様 §2）。
      # 丸ごと削除して次ビルド／vs cover で再生成させる。covers/ は著者ソースのみに
      # なったため触れない。旧配置の残骸掃除だけ 1 リリースの間残す（§6）。
      #
      # @return [Integer] 削除した対象の数
      def clean_cover_files
        deleted = 0
        cache_dir = Common.cover_cache_dir
        if Dir.exist?(cache_dir)
          FileUtils.rm_rf(cache_dir)
          deleted += 1
          Common.log_success("カバー画像キャッシュを削除しました: #{cache_dir}")
        else
          Common.log_info("カバー画像キャッシュは存在しません: #{cache_dir}")
        end

        deleted + clean_legacy_cover_files
      end

      # 旧配置（covers/ 内）の生成物残骸を掃除する（マスター画像・ユーザーSVGは保持）。
      # generated-assets 移設前のプロジェクト向けの移行掃除（§6）。次のリリースで撤去する。
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
      #
      # @return [Integer] 削除した対象の数
      def clean_legacy_cover_files
        covers_dir = Common.covers_dir
        return 0 unless File.directory?(covers_dir)

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

        Common.log_success("旧配置の生成カバー画像を削除しました（.cache へ移設済み・#{deleted_count}ファイル）") if deleted_count.positive?
        deleted_count
      end
    end
  end
end
