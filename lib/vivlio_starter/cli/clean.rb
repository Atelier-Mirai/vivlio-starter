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
#   - ルートの最終成果物・_index_review.md 等: --purge のときだけ
#   - .cache/vs/: ビルドキャッシュ（--cache オプション）
#   - .cache/metrics/: metrics キャッシュ（--cache オプション）
#   - .cache/vs/covers/: 生成されたカバー画像（--cover オプション。covers/ は
#     著者マスターのみになったため触れない）
#
# ルートは掃かない。中間生成物はすべて .cache/vs/build/ に閉じており、ルートに
# 出るのは最終成果物だけなので、パターンで薙ぐ掃除は持たない（V2.0 予定を前倒しで
# 撤去・2026-09-12）。著者が置いた *.html や NN-*.md を巻き込む事故の芽を断つ。
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
      REVIEW_FILE_PATTERNS = %w[
        _index_review.md _index_glossary_review.md
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

      # キャッシュ類（.cache/vs・.cache/metrics）を削除する
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

        # ビルドワークスペース（P4: 現行パイプラインの中間物はすべてここに閉じる）を一括削除
        if File.directory?(Common::BUILD_DIR)
          FileUtils.rm_rf(Common::BUILD_DIR)
          deleted += 1
          Common.log_info("#{Common::BUILD_DIR} を削除しました")
        end

        # ルートに出るのは最終成果物だけ。既定のビルド（Step 0）はそれを残し、
        # 意図が明示された --purge のときだけ手を伸ばす。
        deleted += purge_root_artifacts! if purge

        Common.log_success('不要ファイルの削除が完了しました')
        deleted
      end

      # --purge でルート直下の最終成果物を削除する。
      # ここが `vs clean` がルートへ触れる唯一の場所である。
      #
      # @return [Integer] 削除した対象の数
      def purge_root_artifacts!
        Common.log_action('生成ファイルを削除中...')

        patterns = %w[output.pdf output_compressed.pdf]
        # 索引レビューファイルは著者が編集する入力なので --purge でのみ消す
        patterns.concat(REVIEW_FILE_PATTERNS)
        # 単章 PDF / EPUB（例: 11-install.pdf, 01-life.epub）
        patterns.push('[0-9][0-9]-*.pdf', '[0-9][0-9]-*.epub')
        # 動的ファイル名（project.name 由来）の PDF / EPUB / KPF
        add_dynamic_filename_patterns(patterns)

        deleted = 0
        patterns.each do |pattern|
          Dir.glob(pattern).each do |file|
            next if File.directory?(file)

            FileUtils.rm_f(file)
            deleted += 1
            Common.log_info("#{file} を削除しました")
          end
        end
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
      # 丸ごと削除して次ビルドで再生成させる。
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

        deleted
      rescue StandardError => e
        Common.log_warn("テーマバリアント削除中にエラー: #{e.message}")
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
      # なったため触れない。
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

        deleted
      end

    end
  end
end
