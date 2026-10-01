# frozen_string_literal: true

# ================================================================
# Module: 索引・用語集機能オーケストレーター
# ----------------------------------------------------------------
# 【役割】
# - 索引・用語集機能のエントリポイント
# - IndexMatchScanner, UnifiedPageBuilder, UnifiedTermsManager を統括
# - CLI コマンド（vs index:auto, vs index:apply）の共通ヘルパーを提供
#
# 【処理の流れ】
# 1. vs index:auto: 原稿をスキャンして候補を抽出 → _index_glossary_review.md 生成
# 2. vs index:apply: レビュー結果を適用
# 3. vs build: 索引・用語集ページを生成（パイプライン経由）
#
# 【依存モジュール】
# - IndexMatchScanner: 索引語スキャン・ID付与
# - UnifiedPageBuilder: 索引・用語集ページHTML生成
# - UnifiedTermsManager: 統合用語辞書管理
# - YomiInferrer: MeCab による読み推測
# ================================================================

require_relative 'common'
require_relative 'index/index_match_scanner'
require_relative 'index/unified_page_builder'
require_relative 'index/yomi_inferrer'
require_relative 'index/index_candidate_extractor'
require_relative 'index/scoring_engine'
require_relative 'index/hierarchical_index'
require_relative 'index/unified_terms_manager'
require_relative 'token_resolver'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: IndexCommands
    # ----------------------------------------------------------------
    # 索引機能のヘルパーメソッドを提供
    # CLI コマンド本体は samovar/index_command.rb で定義
    # ================================================================
    module IndexCommands
      module_function

      # ビルドパイプラインから呼び出される索引・用語集処理
      # @param chapters [Array<String>] 対象章のリスト
      def process_index_for_build!(chapters)
        return unless index_enabled?

        require_relative 'index/unified_index_manager'
        manager = UnifiedIndexManager.new
        manager.build_index!(without_excluded_chapters(chapters))
      end

      # 章ごとの索引タグ付けだけを行う（索引ページ・用語集ページは作らない）。
      #
      # なぜ分けるのか（build-mode-parity-spec.md §4）:
      #   索引処理は 2 つの性質を併せ持つ。**章ごとのタグ付け**は 1 章だけで
      #   答えが出るが、**索引ページ・ページ番号・主要参照**は全章そろわないと
      #   決まらない。後者を理由に前者まで単章ビルドから外していたため、
      #   「単章では素のテキスト、全章では索引語」という食い違いが生まれ、
      #   前処理側に埋め合わせ（strip_index_markup!）を置くことになっていた。
      #
      #   タグ付けだけなら章を絞っても正しく動く。全書籍を単位とする警告
      #   （用語集語がビルド対象章に出現しません 等）は呼ばないので、章を絞った
      #   ときの誤検知も起きない——それが full_catalog_scope? ガードの目的だった。
      #
      # 単章と全章で変わらないもの: タグの有無・クラス・data-yomi
      # 単章では正しく出せないもの: 主要参照（他章の出現を知る必要がある）。
      #   ただし index_data の中だけで完結し、出力される要素には現れない。
      #
      # @param chapters [Array<String>] 対象章の basename
      def tag_chapters_for_build!(chapters)
        return unless index_enabled?

        require_relative 'index/index_match_scanner'
        IndexMatchScanner.new(defer_warnings: true).scan_all_chapters!(without_excluded_chapters(chapters),
                                                                       read_only: false)
      end

      # 索引・用語集の対象から外す章（index_glossary.exclude_chapters）を除く。
      #
      # 記法の見本の章（本書の 97 章）は本文の章と同じ語を使うので、語を選ぶだけでは
      # 索引から外せない——「Ruby」「クラス」に見本の章のページが付く。候補の抽出・
      # 章ごとのタグ付け・索引ページのどれも、この章を読まないようにする。
      # タグ付けも外すのは、外した章の本文に用語集の † が残らないようにするため。
      #
      # 書き方は metrics.exclude_chapters と同じ番号・範囲（TokenResolver が解くので
      # スラッグも通る）。単独の番号は特定の章を指すので、改番すると指す章がずれる。
      # vs rename / vs renumber が書き換える（ChapterRename#follow_index_exclusions）。
      # @param chapters [Array<String>] 章の basename（`.md` 付きでもよい）
      # @param tokens [Array] 外す章の指定（既定は book.yml の index_glossary.exclude_chapters）
      # @return [Array<String>]
      def without_excluded_chapters(chapters, tokens: Common::CONFIG.index_glossary.exclude_chapters)
        excluded = excluded_chapter_basenames(tokens)
        return chapters if excluded.empty?

        chapters.reject { excluded.include?(File.basename(it.to_s, '.md')) }
      end

      # 外す章の指定を basename へ解決する。catalog.yml に無い章は指せない
      # （TokenResolver が解決できない指定は無視される）。
      def excluded_chapter_basenames(tokens)
        tokens = Array(tokens).map(&:to_s)
        return [] if tokens.empty?

        TokenResolver::Resolver.new.resolve(tokens).select(&:valid?).map(&:basename)
      end

      # 索引・用語集機能が有効かどうか（実体は Common。前処理も同じ述語を見る）
      def index_enabled? = Common.index_enabled?

      # 対象の章が 1 つも残らなかったとき（名指しした章がすべて除外されているなど）。
      # 空のまま進めると、候補 0 件のレビューファイルで作業中のものを上書きしてしまう。
      # @return [Integer] 終了コード（何もしなかっただけなので 0）
      def report_no_chapters
        Common.log_warn('索引の対象になる章がないため、何もしませんでした')
        0
      end

      # 対象章を解決
      # @param tokens [Array<String>] 対象章トークン（省略時は全章）
      def resolve_chapters(tokens)
        resolver = TokenResolver::Resolver.new
        entries = resolver.resolve(tokens)

        if entries.any?
          basenames = entries.select(&:valid?).map(&:basename)
          Common.log_info("引数から対象章を特定しました: #{basenames.join(', ')}")
          kept = without_excluded_chapters(basenames)
          # 名指しした章を黙って落とすと、指定が効かなかった理由が分からない
          dropped = basenames - kept
          Common.log_warn("次の章は index_glossary.exclude_chapters により索引の対象外です: #{dropped.join(', ')}") if dropped.any?
          kept
        else
          begin
            require_relative 'build/catalog_loader'
            chapters = without_excluded_chapters(Build::CatalogLoader.load_existing_basenames)
            Common.log_info("catalog.yml から対象章を特定しました: #{chapters.size} 章")
            chapters
          rescue StandardError => e
            Common.log_warn("catalog.yml の読み込みに失敗したため、全 Markdown ファイルを対象にします: #{e.message}")
            chapters = Dir.glob('*.md').map { |f| File.basename(f, '.md') }.sort
            Common.log_info("カレントディレクトリの全ファイルを対象にします: #{chapters.size} 章")
            chapters
          end
        end
      end
      module_function :resolve_chapters
    end
  end
end
