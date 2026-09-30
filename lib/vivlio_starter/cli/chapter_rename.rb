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
#   設定は追随しない。この値は前書き・本文・付録・後書きの区分そのもので、
#   `vs renumber` は区分の内側でしか番号を振らないため、改番で見直す必要が生じない。
#   `index_glossary.exclude_chapters` の単独の番号（`[97]`）は特定の章を指すので追随させる
#   （範囲は metrics と同じく番号帯として扱い、書き換えない）。
#   （以前は改番のたびに見直しを促す案内を出していたが、見直す対象が無いのに毎回
#   出るノイズだったので撤去した。）
#
# 仕様: chapter-rename-followers-spec.md
# ================================================================

require_relative 'common'
require_relative 'build/catalog_updater'
require_relative 'index/unified_terms_manager'
require_relative 'masking'
require_relative 'pre_process/cross_reference_processor'

module VivlioStarter
  module CLI
    # 章名の変更に追随すべき処理の登録簿
    module ChapterRename
      module_function

      # 追随先 1 件。label は失敗時のメッセージに使う。
      #
      # batch: true の追随先は、1 章ずつではなく**改名の対応表全体**を一度に受け取る
      # （handler.call({ 旧 => 新, … })）。章番号で書かれた値を追う追随先のためで、
      # 1 章ずつ置き換えると `--step 2` の 12→13・13→15 で `12` が 13 を経て 15 まで
      # 動いてしまう。basename で書かれた値（catalog・索引辞書）は一意なので 1 章ずつでよい。
      Follower = Data.define(:label, :handler, :batch) do
        def initialize(label:, handler:, batch: false) = super
      end

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

      # 本文の章参照（`@ch-slug`・`@pageref:ch-slug`・`@chapref:ch-slug`）を新しいスラッグへ
      # 書き換える（chapter-reference-spec.md §2.2）。章ラベルはスラッグから付くので、
      # 改番だけ（スラッグが変わらない）なら何もしない。参照は著者が書いたものだが、
      # 旧ラベルは改名で消えて指す先がなくなるので、索引辞書の main: と同じく機械的に書き換える。
      def follow_chapter_references(old_basename, new_basename)
        old_id = PreProcessCommands::CrossReferenceProcessor.chapter_label_id_for(old_basename)
        new_id = PreProcessCommands::CrossReferenceProcessor.chapter_label_id_for(new_basename)
        return if old_id.nil? || new_id.nil? || old_id == new_id

        count = rewrite_chapter_references(old_id, new_id)
        return if count.zero?

        Common.log_result("本文の章参照 #{count} 箇所を @#{old_id} から @#{new_id} へ書き換えました", status: :success)
      end

      # contents/*.md の章参照を書き換え、書き換えた数を返す。コードブロックとインラインコードの
      # 中（記法の説明に書いた例）は書き換えない。write: false なら数えるだけ（改名の確認の画面用）。
      def rewrite_chapter_references(old_id, new_id, write: true)
        pattern = /(?<![a-zA-Z0-9_.])@((?:pageref:|chapref:)?)#{Regexp.escape(old_id)}(?![\w-])/
        Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).sum do |path|
          text = File.read(path, encoding: 'utf-8')
          protected_text, spans = Masking.protect_code(text)
          count = protected_text.scan(pattern).size
          if write && count.positive?
            replaced = protected_text.gsub(pattern) { "@#{Regexp.last_match(1)}#{new_id}" }
            File.write(path, Masking.restore_code(replaced, spans))
          end
          count
        end
      end

      # book.yml の index_glossary.exclude_chapters（改善案 #97）。1 行の配列で書かれた値だけを扱う。
      EXCLUSION_LINE = /^(?<head>[ \t]+exclude_chapters:[ \t]*)\[(?<body>[^\]\n]*)\]/

      # 索引から外す章（book.yml の index_glossary.exclude_chapters）を改名に追随させる。
      #
      # 本書は見本の 97 章を `[97]` と番号で外している。metrics.exclude_chapters と
      # 同じ書き方にそろえ、範囲も書けるようにするためで、そのぶん改番で指す章が
      # ずれる。ここで番号・スラッグ・basename の指定を新しい名前へ書き換える。
      # **範囲（`90-98`）は書き換えない**——metrics と同じく番号帯そのものを指す書き方で、
      # 帯の中で番号が動いても指す範囲は変わらないため。
      #
      # book.yml は著者のコメントを抱えているので、YAML を書き戻さずにその 1 行だけを直す
      # （metrics にも同名のキーがあるので、`index_glossary:` 節の中に限る）。
      # @param renames [Hash{String => String}] 旧 basename => 新 basename
      def follow_index_exclusions(renames)
        path = Common::CONFIG_FILE
        return unless File.file?(path)

        text = File.read(path, encoding: 'utf-8')
        section = index_glossary_section_range(text) or return
        matched = EXCLUSION_LINE.match(text[section]) or return

        tokens = matched[:body].split(',').map(&:strip).reject(&:empty?)
        rewritten = rewrite_exclusion_tokens(tokens, renames)
        return if rewritten == tokens

        text[section] = text[section].sub(EXCLUSION_LINE) { "#{matched[:head]}[#{rewritten.join(', ')}]" }
        File.write(path, text, encoding: 'utf-8')
        Common.log_result(
          "book.yml の index_glossary.exclude_chapters を [#{tokens.join(', ')}] から [#{rewritten.join(', ')}] へ書き換えました",
          status: :success
        )
      end

      # 外す章の指定を、改名の対応表で**同時に**置き換える（連鎖させない）。
      # 番号は 2 桁にそろえて照合し、書き換えた値も 2 桁で書く（`[00, 90-98, 99]` と同じ）。
      # @param tokens [Array<String>] 配列の要素（book.yml に書かれたまま）
      # @param renames [Hash{String => String}] 旧 basename => 新 basename
      # @return [Array<String>]
      def rewrite_exclusion_tokens(tokens, renames)
        table = renames.each_with_object({}) do |(old_basename, new_basename), map|
          old_number, old_slug = old_basename.split('-', 2)
          new_number, new_slug = new_basename.split('-', 2)
          map[old_number] = new_number
          map[old_slug] = new_slug if old_slug && new_slug
          map[old_basename] = new_basename
        end

        tokens.map do |token|
          bare = token.delete(%('"))
          key = bare.match?(/\A\d+\z/) ? format('%02d', bare.to_i) : bare
          table.fetch(key, token)
        end
      end

      # book.yml の `index_glossary:` 節の範囲（次の最上位キーの手前まで）
      def index_glossary_section_range(text)
        start = text.index(/^index_glossary:[ \t]*(?:#.*)?$/) or return nil
        finish = text.index(/^[^\s#]/, start + 1) || text.size
        start...finish
      end

      # 追随先の登録簿。**ここへ 1 行足すだけ**で rename / renumber の両方に効く。
      FOLLOWERS = [
        Follower.new(label: 'catalog.yml', handler: method(:follow_catalog)),
        Follower.new(label: '画像ディレクトリ', handler: method(:follow_image_dir)),
        Follower.new(label: '索引辞書', handler: method(:follow_index_dictionary)),
        Follower.new(label: '本文の章参照', handler: method(:follow_chapter_references)),
        Follower.new(label: 'book.yml の index_glossary.exclude_chapters', handler: method(:follow_index_exclusions), batch: true)
      ].freeze

      # 章名の変更を全追随先へ伝える（1 章ぶん）。
      # @param old_basename [String] 例 '21-markdown-tutorial'
      # @param new_basename [String] 例 '20-markdown-tutorial'
      # @param followers [Array<Follower>] 差し替え用（テストで失敗経路を作るため）
      def follow!(old_basename, new_basename, followers: FOLLOWERS)
        follow_all!({ old_basename => new_basename }, followers:)
      end

      # 章名の変更をまとめて全追随先へ伝える（vs renumber）。
      #
      # **1 つが失敗しても止めない。** 原稿ファイルの移動は追随より先に済んでいるので、
      # 途中で abort すると「ファイルは新しい名前、catalog は古い名前」という中途半端な
      # 状態が残る。追随できなかったものを名指しで警告して先へ進むほうが復旧しやすい。
      #
      # @param renames [Hash{String => String}] 旧 basename => 新 basename
      # @param followers [Array<Follower>] 差し替え用
      def follow_all!(renames, followers: FOLLOWERS)
        followers.each do |follower|
          if follower.batch
            guard(follower, renames) { follower.handler.call(renames) }
          else
            renames.each { |old, new| guard(follower, old => new) { follower.handler.call(old, new) } }
          end
        end
      end

      # 追随先 1 件を実行し、失敗したら名指しで知らせて先へ進む
      def guard(follower, renames)
        yield
      rescue StandardError => e
        Common.log_warn(
          "#{follower.label} が章名の変更に追随できませんでした: #{e.message}",
          detail: "#{renames.map { |old, new| "#{old} → #{new}" }.join('、')} の変更を手作業で反映してください"
        )
      end
    end
  end
end
