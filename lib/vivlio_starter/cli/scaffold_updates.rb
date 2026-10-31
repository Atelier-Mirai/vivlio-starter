# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/scaffold_updates.rb
# ================================================================
# 責務:
#   雛形の CSS と book.yml の新しいキーを、著者へ知らせる（改善案.md #117・#118）。
#   全章の vs build・vs preflight は件数だけを 💡 で知らせ、vs upgrade が
#   増えたキーを book.yml へ足す。判定をここに集め、どちらも同じものを見る。
#
# なぜ book.yml を祖先の雛形と比べないか:
#   book.yml は著者データなので .cache/vs/scaffold-base/ に保存されず、古い gem の
#   雛形は gem cleanup や Ruby の入れ替えで消える。lock にキーの一覧（book_keys）を
#   持てば、どちらにも頼らずに済む（scaffold-update-notice-spec.md §3.3）。
#
# なぜ CSS だけを見るか:
#   雛形全体（7,755 件）のハッシュは約 4 秒かかるが、CSS の 27 件なら 2.5 ms で済む。
#   崩れが紙面に出るのも CSS で、README.md や Gemfile の変更まで知らせると埋もれる（§3.1）。
# ================================================================

require_relative 'book_key_inserter'
require_relative 'common'
require_relative 'config_keys'
require_relative 'new'
require_relative 'retired_key_remover'
require_relative 'scaffold_lock'
require_relative '../version'

module VivlioStarter
  module CLI
    module ScaffoldUpdates
      extend self

      # vs build all が子のビルドへ渡す。全巻を組み終えた親が 1 回だけ知らせる
      SILENT_ENV = 'VS_SKIP_SCAFFOLD_NOTICE'

      STYLESHEET_GLOB = 'stylesheets/**/*.css'

      # 全章のビルドの終わりの知らせ。ビルドの結果は変えず、読めなければ黙る（§6）。
      def report(scaffold_source: NewCommands::SCAFFOLD_SOURCE)
        return if ENV[SILENT_ENV]

        lock = ScaffoldLock.read
        return if lock.nil? || newer_than_gem?(lock)

        stylesheets = stale_stylesheets(lock, scaffold_source)
        keys = new_book_keys(lock, scaffold_source)
        return if stylesheets.empty? && keys.empty?

        Common.log_always("💡 雛形が新しくなっています（#{summary(stylesheets, keys)}）")
        Common.log_always("#{Common::DETAIL_INDENT}vs upgrade で確かめられます")
      rescue StandardError => e
        Common.log_debug("[scaffold] 雛形の更新を確かめられませんでした: #{e.message}")
      end

      # 増えたキーを book.yml へ差し込んだ結果を返す。書き込むのは vs upgrade（§10）。
      # @param lock [Hash, nil] 雛形を取り込む前の lock。無ければ判定できないので何もしない
      # @return [BookKeyInserter::Result, nil] 増えたキーが無ければ nil
      def plan_new_book_keys(lock, scaffold_source:)
        return if lock.nil?

        keys = new_book_keys(lock, scaffold_source)
        return if keys.empty?

        BookKeyInserter.insert(File.read(ScaffoldLock::BOOK_RELATIVE, encoding: 'utf-8'), scaffold_book(scaffold_source), keys)
      rescue StandardError => e
        Common.log_debug("[scaffold] 増えた設定を確かめられませんでした: #{e.message}")
        nil
      end

      # vs upgrade の最後に、足した設定を知らせる。足せなかった設定は行のまま並べる（§10）
      # @param plan [BookKeyInserter::Result, nil]
      def report_new_book_keys(plan, scaffold_source:, dry_run: false)
        return if plan.nil?

        return report_planned_keys(plan, scaffold_source) if dry_run

        report_added_keys(plan.added)
        report_skipped_keys(plan.skipped, scaffold_source)
      end

      # 新しくなっている CSS（プロジェクトからの相対パス・名前順）。
      # vs upgrade で断ったときと同じ雛形なら、次に雛形が変わるまで言わない（§3.2）
      def stale_stylesheets(lock, scaffold_source)
        Dir.glob(STYLESHEET_GLOB, base: scaffold_source).sort.select do |relative|
          digest = ScaffoldLock.file_digest(File.join(scaffold_source, relative))
          lock[:declined][relative] != digest && ScaffoldLock.classify(relative, digest, lock[:files]) != :latest
        end
      end

      # 増えたキー（雛形の並び）。親ごと増えたときは親だけを返す（§3.3）
      # @return [Array<String>] 例: ["theme.lead_size"]
      def new_book_keys(lock, scaffold_source)
        scaffold_text = scaffold_book(scaffold_source)
        written = ScaffoldLock.book_keys(File.read(ScaffoldLock::BOOK_RELATIVE, encoding: 'utf-8'))
        fresh = ScaffoldLock.book_keys(scaffold_text) - Array(lock[:book_keys]) - written - moved_targets(written)
        fresh.reject { fresh.include?(it.rpartition('.').first) }
      end

      private

      # --dry-run: 足す行をそのまま見せる
      def report_planned_keys(plan, scaffold_source)
        keys = plan.added + plan.skipped
        Common.log_always("💡 book.yml に書ける設定が #{keys.size} つ増えました（vs upgrade で足します。値は既定値です）")
        print_listing(scaffold_source, keys)
      end

      def report_added_keys(keys)
        return if keys.empty?

        indent = Common::DETAIL_INDENT
        Common.log_result("book.yml に新しい設定を #{keys.size} つ足しました（値は既定値なので、組み上がりは変わりません）", status: :success)
        keys.each { Common.log_always("#{indent}#{it}") }
        Common.log_always("#{indent}説明は vs config:book #{keys.first} のように調べられます")
      end

      def report_skipped_keys(keys, scaffold_source)
        return if keys.empty?

        Common.log_always("💡 book.yml へ自動で足せなかった設定が #{keys.size} つあります（書かなくても既定値で動きます）")
        Common.log_always("#{Common::DETAIL_INDENT}使うときは、次の行を config/book.yml へ写してください")
        print_listing(scaffold_source, keys)
      end

      def print_listing(scaffold_source, keys)
        Common.log_always('')
        key_lines(scaffold_book(scaffold_source), keys).each { Common.log_always("#{Common::DETAIL_INDENT}#{it}") }
      end

      def scaffold_book(scaffold_source)
        File.read(File.join(scaffold_source, ScaffoldLock::BOOK_RELATIVE), encoding: 'utf-8')
      end

      # 著者がまだ書いている廃止キーの、値の移し先。vs upgrade が値を移すので新しいキーではない
      def moved_targets(written)
        ConfigKeys.moves.filter_map { |from, to| to.join('.') if written.include?(from.join('.')) }
      end

      def newer_than_gem?(lock)
        Gem::Version.new(lock[:version].to_s) > Gem::Version.new(VivlioStarter::VERSION)
      end

      def summary(stylesheets, keys)
        parts = []
        if stylesheets.any?
          others = stylesheets.size > 1 ? " ほか #{stylesheets.size - 1} 件" : ''
          parts << "CSS: #{File.basename(stylesheets.first)}#{others}"
        end
        parts << "book.yml の設定: #{keys.size} 件" if keys.any?
        parts.join('・')
      end

      # 雛形の行をそのまま、親のキーをつけて並べる。ドット区切りは YAML に写せない（§1.2）
      def key_lines(scaffold_text, keys)
        lines = scaffold_text.lines(chomp: true)
        printed = []

        keys.map { written_path(lines, it.split('.')) }.uniq.flat_map do |path|
          parents = (1...path.size).map { path.first(it) }.reject { printed.include?(it) }
          printed.concat(parents)

          header = parents.map { "#{'  ' * (it.size - 1)}#{it.last}:" }
          header + lines[RetiredKeyRemover.block_range(lines, path)]
        end
      end

      # キーの行があるパス。`section: { min: 1, max: 9 }` の min には自分の行が無いので、
      # 1 行にまとめて書いた親をたどる
      def written_path(lines, path)
        path = path[0...-1] until RetiredKeyRemover.block_range(lines, path)
        path
      end
    end
  end
end
