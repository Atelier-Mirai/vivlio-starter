# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/clean.rb
# ================================================================
# 責務:
#   キャッシュとビルドの生成物を削除する。
#
# vs clean の削除対象:
#   - (なし): キャッシュ（.cache/ を丸ごと。ビルドの作業フォルダ .cache/vs/build/ もここ）
#   - --purge: キャッシュに加えて、ルート直下の生成物（PDF・EPUB・KPF・表紙の JPEG・
#     索引のレビューファイル）
#   - --index-dictionaries: 索引・用語集の辞書だけ（確認あり）
#
# キャッシュはどれも次のビルドで作り直せるので、種類ごとに選ばせない（表紙・扉絵の
# 生成画像も .cache/vs/ の下にある）。vs upgrade の退避は .vs-backup/ に置き、
# キャッシュと一緒に消えないようにしてある。
#
# ルートは --purge のときだけ、決まった名前の生成物に限って触れる。パターンで薙ぐ
# 掃除は持たない（著者が置いた *.html や NN-*.md を巻き込む事故の芽を断つ）。
#
# vs build・vs preflight・章番号の付け直しの後始末は clean_build_workspace で、
# 作業フォルダだけを消す。キャッシュは残す（作り直すとビルドが遅くなる）。
#
# 依存:
#   - Common: 設定読み込み・ログ出力・パス定数
# ================================================================

require 'fileutils'

module VivlioStarter
  module CLI
    # キャッシュとビルド生成物の削除
    module CleanCommands
      module_function

      # キャッシュの置き場。vs が作るキャッシュ（.cache/vs・.cache/metrics・
      # .cache/spellcheck-dictionaries など）はすべてこの下にある。
      CACHE_ROOT = '.cache'

      # 索引レビューファイル。`vs index:auto` が書き出すが、そこから先は
      # **著者が編集する入力**であって中間生成物ではない。ビルドのたびに消すと、
      # 「除外済みリストから戻す語を選ぶ」ような途中の判断がまるごと失われ、
      # `vs index:apply` は「ファイルが見つかりません」で終わる。
      # 掃除するのは意図が明示された `--purge` のときだけにする。
      REVIEW_FILE_PATTERNS = %w[_index_glossary_review.md].freeze

      # 削除結果の内訳。表示は呼び出し側の責務とし、ドメイン層は件数を返すだけにする。
      # declined は、辞書の削除を確認で断ったか（「削除対象はありませんでした」と区別する）。
      CleanSummary = Data.define(:cache, :artifacts, :dictionaries, :declined) do
        def initialize(cache:, artifacts:, dictionaries:, declined: false) = super
        def total = cache + artifacts + dictionaries
        def none? = total.zero?
      end

      # vs clean の本体
      #
      # @param option_hash [Hash]
      #   - :purge [Boolean] ルート直下の生成物も削除する
      #   - :index_dictionaries [Boolean] 索引・用語集の辞書を削除する（確認あり）。
      #     これだけを指定したときはキャッシュに触れない
      # @return [CleanSummary] 削除した対象の内訳
      def execute_clean(option_hash)
        opts = option_hash || {}

        dictionaries = opts[:index_dictionaries] ? clean_index_dictionaries : 0
        declined = dictionaries.nil?
        dictionaries ||= 0
        if opts[:index_dictionaries] && !opts[:purge]
          return CleanSummary.new(cache: 0, artifacts: 0, dictionaries:, declined:)
        end

        cache = clean_cache_files
        artifacts = opts[:purge] ? purge_root_artifacts! : 0
        CleanSummary.new(cache:, artifacts:, dictionaries:, declined:)
      end

      # ビルドの作業フォルダだけを削除する（vs build・vs preflight・章番号の付け直し）。
      # 前回の HTML が次の組版へ混ざらないようにする。キャッシュは残す。
      def clean_build_workspace = FileUtils.rm_rf(Common::BUILD_DIR)

      # .cache/ を丸ごと削除する
      #
      # @return [Integer] 削除した .cache/ 直下の項目の数
      def clean_cache_files
        return 0 unless File.directory?(CACHE_ROOT)

        entries = Dir.children(CACHE_ROOT)
        Common.log_action("キャッシュを削除中: #{CACHE_ROOT}/")
        FileUtils.rm_rf(CACHE_ROOT)
        entries.size
      end

      # --purge でルート直下の生成物を削除する。
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
      #   - vivlio_starter_frontcover*.jpg（KDP へ上げる電子書籍用の表紙）
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
        patterns << "#{project_name}_frontcover*.jpg"
      end

      # 索引・用語集辞書データを削除する（確認プロンプトあり）
      #
      # @return [Integer, nil] 削除した対象の数（対象が無いときは 0、確認で断ったときは nil）
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
        return nil unless Common.confirm?('本当に削除しますか？')

        targets.each do |f|
          FileUtils.rm_f(f)
          Common.log_success("削除しました: #{f}")
        end
        targets.size
      end
    end
  end
end
