# frozen_string_literal: true

# ================================================================
# Module: ChapterRename
# ----------------------------------------------------------------
# 責務:
#   章名（basename）の変更に追随すべき処理の**唯一の登録簿**。
#
# なぜ登録制にするか:
#   basename はプロジェクト内の複数の場所から参照されている。追随先が増える
#   たびに `vs rename` と `vs renumber` の 2 経路へ直書きしていくと、同じ処理が
#   倍で増える（実際、画像ディレクトリの移動は衝突時の警告文まで含めて 2 箇所へ
#   コピーされていた）。**FOLLOWERS へ 1 行足すだけ**で両経路に効く形にする。
#
# 追随しないものもある:
#   `metrics.exclude_chapters: [00, 90-98, 99]` のように**章番号の範囲**で書かれた
#   設定は追随しない。`90-98` が「付録すべて」の意図なのか特定の章なのかを機械が
#   判断できず、黙って書き換えるほうが危険なため。改番後に案内するに留める。
#
# 仕様: chapter-rename-followers-spec.md
# ================================================================

require_relative 'common'
require_relative 'build/catalog_updater'
require_relative 'index/unified_terms_manager'

module VivlioStarter
  module CLI
    # 章名の変更に追随すべき処理の登録簿
    module ChapterRename
      module_function

      # 追随先 1 件。label は失敗時のメッセージに使う。
      Follower = Data.define(:label, :handler)

      # catalog.yml の章名を差し替える
      def follow_catalog(old_basename, new_basename)
        Build::CatalogUpdater.rename_chapter(old_basename, new_basename)
      end

      # images/<basename>/ を移す。
      # 移動先が既にあるときは統合の判断が要るので、上書きせず著者へ委ねる。
      def follow_image_dir(old_basename, new_basename)
        old_dir = File.join(Common::IMAGES_DIR, old_basename)
        return unless File.directory?(old_dir)

        new_dir = File.join(Common::IMAGES_DIR, new_basename)
        if File.exist?(new_dir)
          Common.log_warn("#{new_dir} が既に存在するため、画像ディレクトリは手動で統合してください")
          return
        end

        FileUtils.mv(old_dir, new_dir)
      end

      # 索引辞書が持つ章名（main: と scanned_chapters）を差し替える。
      # main: は著者の判断＝一次データなので、実在しない章を指していても捨てられない
      # ——contexts のように「捨てて本文から拾い直す」ことができない。
      def follow_index_dictionary(old_basename, new_basename)
        UnifiedTermsManager.new.rename_chapter!(old_basename, new_basename)
      end

      # 追随先の登録簿。**ここへ 1 行足すだけ**で rename / renumber の両方に効く。
      FOLLOWERS = [
        Follower.new(label: 'catalog.yml', handler: method(:follow_catalog)),
        Follower.new(label: '画像ディレクトリ', handler: method(:follow_image_dir)),
        Follower.new(label: '索引辞書', handler: method(:follow_index_dictionary))
      ].freeze

      # 章名の変更を全追随先へ伝える。
      #
      # **1 つが失敗しても止めない。** 原稿ファイルの移動は追随より先に済んでいるので、
      # 途中で abort すると「ファイルは新しい名前、catalog は古い名前」という中途半端な
      # 状態が残る。追随できなかったものを名指しで警告して先へ進むほうが復旧しやすい。
      #
      # @param old_basename [String] 例 '21-markdown-tutorial'
      # @param new_basename [String] 例 '20-markdown-tutorial'
      # @param followers [Array<Follower>] 差し替え用（テストで失敗経路を作るため）
      def follow!(old_basename, new_basename, followers: FOLLOWERS)
        followers.each do |follower|
          follower.handler.call(old_basename, new_basename)
        rescue StandardError => e
          Common.log_warn(
            "#{follower.label} が章名の変更に追随できませんでした: #{e.message}",
            detail: "#{old_basename} → #{new_basename} の変更を手作業で反映してください"
          )
        end
      end
    end
  end
end
