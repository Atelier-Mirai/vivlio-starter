# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/plan.rb
# ================================================================
# 責務:
#   ビルドの段を走らせるかどうかの材料を、一つにまとめる（v2-architecture-spec.md §3.2）
#
# UnifiedBuildPipeline はビルドの開始時に BuildPlan.resolve を一度だけ呼び、段の表の
# 条件の列は plan だけを読む。段を走らせるかどうかが表だけで読め、ビルドの途中で
# 設定を読み直して結果が変わることが無い。
# ================================================================

require_relative 'targets'
require_relative 'whole_toc_generator'

module VivlioStarter
  module CLI
    # 段の条件になる、機能の有効・無効（v2-architecture-spec.md §6 の表の「窓口」の列と、
    # 段の表が今まで設定から直接読んでいたもの）
    #
    # @!attribute index                 索引・用語集（index_glossary.enabled）
    # @!attribute techbook_post_process Type 3 対策（output.pdf.techbook）
    # @!attribute web_novel             小説投稿サイトの記法（notation.web_novel）。読む段は S8 で足す
    # @!attribute print_full_bleed      本文にフチなしの要素がある（output.print_pdf.full_bleed）
    # @!attribute pdf_cover             閲覧用 PDF に表紙を綴じる（output.pdf.combined）
    # @!attribute epub_cover            EPUB に表紙を埋める（output.epub.embed）
    # @!attribute whole_toc             全巻目次を載せる巻である（分冊）
    BuildFeatures = Data.define(:index, :techbook_post_process, :web_novel,
                                :print_full_bleed, :pdf_cover, :epub_cover, :whole_toc)

    # 出力先・軸・機能の組。段の表の条件の列が読む、ただ一つの材料
    BuildPlan = Data.define(:targets, :traits, :features) do
      # 今の設定と、選ばれている巻から作る。
      #
      # 機能の値は Common の述語を通して読む（索引は Common.index_enabled?）。同じ設定を
      # 段の中の処理（索引のページを並べる・しおりを作る）も読むので、読み方を二つにしない。
      #
      # @param targets [Build::Targets] 出力先（直接ビルドとテストは、設定と違う組を渡す）
      # @return [BuildPlan]
      def self.resolve(targets: Build::Targets.resolve)
        config = Common::CONFIG
        new(targets:, traits: Common.traits,
            features: BuildFeatures.new(
              index: Common.index_enabled?,
              techbook_post_process: config&.dig(:output, :pdf, :techbook) == true,
              web_novel: Common.truthy?(config&.dig(:notation, :web_novel)),
              print_full_bleed: Common.print_pdf_full_bleed?,
              pdf_cover: Common.pdf_combined?,
              epub_cover: Common.epub_embed?,
              whole_toc: Build::WholeTocGenerator.needed?
            ))
      end

      # ビルド中の plan。パイプラインが開始時に置き、終わりに外す（install）。
      # 段の中の処理（前処理の段の表）は、設定を読み直さずにこれを読む。
      # パイプラインの外（テスト・単独の前処理）では、その場の設定から作る
      # @return [BuildPlan]
      def self.current = @current || resolve

      # ビルド中の plan を置く（nil で外す）。ブロックを渡すと、抜けるときに前の値へ戻す
      # @param plan [BuildPlan, nil]
      def self.install(plan)
        previous = @current
        @current = plan
        return unless block_given?

        begin
          yield
        ensure
          @current = previous
        end
      end

      # 入稿用 PDF を閲覧用 PDF から導出するか。導出するときは、print_pdf だけの本でも
      # 閲覧用の中間 PDF が要る。フチなしの要素がある本は塗り足しを復元できないので、個別に組む
      def derive_print? = targets.print_pdf && !features.print_full_bleed

      # 本文・前付・奥付の閲覧用 PDF を組むか（最終成果物にするかは targets.pdf）
      def viewing_pdf? = targets.pdf || derive_print?

      # 回転テーブルのページを画像にする段を PDF 枝が担うか。Kindle を作らないビルドでは不要、
      # 本文 PDF を作らないビルドでは不能（素の表になり、Kindle 枝が 🟡 で案内する）
      def rotate_table_images? = targets.kindle && viewing_pdf?

      # 表紙の PDF・JPG を読む枝があるか。閲覧用 PDF は結合が有効なときだけ表紙を綴じ、
      # EPUB・Kindle は埋め込みが有効なときだけ表紙の JPG を埋める
      def cover_assets? = (targets.pdf && features.pdf_cover) || targets.print_pdf ||
                          (targets.epub_or_kindle? && features.epub_cover)
    end
  end
end
