# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/upgrade.rb
# ================================================================
# 責務:
#   既存プロジェクトを新しい gem の雛形へ追従させる（`vs upgrade` のドメイン層）。
#   docs/specs/project-upgrade-command-spec.md の実装。
#
# 仕組み（三者比較）:
#   config/scaffold.lock（展開時の雛形ハッシュ）・現在の雛形・プロジェクト現物の
#   3 点から各ファイルを 追加/更新/競合/保持/最新 に分類する。
#   - 追加: 雛形の新規ファイル → コピー
#   - 更新: 雛形が改良・著者は未変更 → 自動適用可（--yes で無確認）
#   - 競合: 雛形も著者も変更 → diff 提示・個別確認（y/n/d）
#   - 保持: 著者データ領域（ScaffoldLock::AUTHOR_DATA_*）→ 絶対に触れない
#
# 安全策:
#   - 上書き前に必ず .cache/vs/upgrade-backup/<timestamp>/ へ元ファイルを退避
#   - --dry-run はファイルシステムに一切書き込まない（lock 含む）
# ================================================================

require 'fileutils'

require_relative 'scaffold_lock'
require_relative 'new'
require_relative '../version'

module VivlioStarter
  module CLI
    module UpgradeCommands
      extend self

      # 計画表の 1 行。status: :add / :add_empty / :update / :conflict / :keep
      PlanItem = Data.define(:relative, :status)

      # 著者辞書がプロジェクトに存在しない場合にだけ追加する「空の辞書」。
      # 雛形のサンプル辞書（開発リポジトリの実辞書）を配ると著者の本に無関係な
      # 用語が混入するため、空の初期形を用意する。
      EMPTY_DICTIONARY_TEMPLATES = {
        File.join('config', 'index_glossary_terms.yml') => <<~YAML,
          # 索引・用語集の統合辞書（vs index:auto → vs index:apply が管理します）
          terms: []
        YAML
        File.join('config', 'index_glossary_rejected.yml') => <<~YAML,
          # 索引候補の却下リスト（vs index:apply が管理します）
          rejected_terms: []
        YAML
        File.join('config', 'user_words.txt') => <<~TEXT,
          # ユーザー辞書（このプロジェクトのスペルチェック許可語）
          # 1 行 1 語。# 始まりはコメント。辞書順・重複なしで自動管理されます。
          # `vs lint --register` を実行すると、スペルチェックで未知だった語がここへ追加されます。
        TEXT
        File.join('config', 'textlint_allowlist.yml') => <<~YAML
          # textlint-filter-rule-allowlist で使用する除外語句リスト
          # 書籍名、資格名称、専門用語など、プロジェクト固有の除外対象を記載します
          # 正規表現も使用可能（例: "/pattern/flags"）
          []
        YAML
      }.freeze

      DIFF_PREVIEW_LINES = 20

      # 比較元の雛形ディレクトリ。テストではフィクスチャ雛形に差し替える（DI）。
      attr_writer :scaffold_source

      def scaffold_source = @scaffold_source || NewCommands::SCAFFOLD_SOURCE

      # Samovar `UpgradeCommand` から呼び出すメイン処理（終了コードを返す）
      def run_from_command(cmd)
        # --- Phase: 分類（三者比較） ---
        Common.log_summary("雛形との差分を確認しています…（gem #{VivlioStarter::VERSION} の雛形）")
        scaffold_digests = ScaffoldLock.digest_scaffold(scaffold_source)
        lock = ScaffoldLock.read
        warn_missing_lock if lock.nil?
        plan = build_plan(scaffold_digests, lock)

        # --- Phase: 計画表示 ---
        display_plan(plan)
        actionable = plan.reject { it.status == :keep }
        if actionable.empty?
          Common.log_result('プロジェクトは雛形の最新状態です。', status: :success)
          record_lock!(scaffold_digests, lock, applied: []) unless cmd.options[:dry_run]
          return 0
        end
        return finish_dry_run(actionable) if cmd.options[:dry_run]

        # --- Phase: 適用（追加・更新 → 競合の個別確認） ---
        applied, skipped, backup_dir = apply_plan(cmd, plan, scaffold_digests)
        return 0 if applied.nil? # 全体確認で中止

        # --- Phase: lock 更新・完了報告 ---
        record_lock!(scaffold_digests, lock, applied:)
        print_summary(plan, applied, skipped, backup_dir)
        0
      end

      private

      def warn_missing_lock
        Common.log_warn('scaffold.lock が見つかりません（本機能導入前のプロジェクト）。現物と雛形を直接比較し、差分のあるファイルは安全側に倒してすべて「競合」として確認します。')
      end

      # 雛形の全ファイルを §1.2 の表にしたがって分類する
      # @param scaffold_digests [Hash{String => String}] 現在の雛形のハッシュ表
      # @param lock [Hash, nil] ScaffoldLock.read の結果
      # @return [Array<PlanItem>] :latest（表示不要）は含まない
      def build_plan(scaffold_digests, lock)
        lock_files = lock&.dig(:files) || {}

        scaffold_digests.filter_map do |relative, scaffold_digest|
          status =
            if ScaffoldLock.author_data?(relative)
              classify_author_data(relative, scaffold_digest, lock_files, lock)
            else
              classify_managed(relative, scaffold_digest, lock_files)
            end
          PlanItem.new(relative:, status:) unless status.nil? || status == :latest
        end
      end

      # 著者データ領域の分類
      # @return [Symbol, nil] :add_empty / :keep / nil（表示不要）
      def classify_author_data(relative, scaffold_digest, lock_files, lock)
        unless File.exist?(relative)
          # 著者辞書が無い場合のみ「空の辞書」を追加（雛形サンプルは配らない）
          return EMPTY_DICTIONARY_TEMPLATES.key?(relative) ? :add_empty : nil
        end

        # 雛形側が変わったときだけ「保持（対象外）」を 1 度だけ知らせる。
        # lock なしの旧プロジェクトでは現物との直接比較で代用する。
        reference = lock ? lock_files[relative] : ScaffoldLock.file_digest(relative)
        reference == scaffold_digest ? nil : :keep
      end

      # 雛形管理ファイル（著者データ以外）の分類（§1.2 の表）
      def classify_managed(relative, scaffold_digest, lock_files)
        return :add unless File.exist?(relative)

        current_digest = ScaffoldLock.file_digest(relative)
        lock_digest = lock_files[relative]

        if lock_digest.nil?
          # lock なし（旧プロジェクト or 追跡外ファイル）: 一致なら最新、不一致は安全側で競合
          current_digest == scaffold_digest ? :latest : :conflict
        elsif scaffold_digest == lock_digest then :latest
        elsif current_digest == lock_digest  then :update
        else                                      :conflict
        end
      end

      STATUS_LABELS = {
        add: ['追加', '雛形の新規ファイル'],
        add_empty: ['追加', '著者辞書が無いため空の辞書を用意'],
        update: ['更新', '雛形が改良・あなたは未変更 → 自動適用可'],
        conflict: ['競合', '雛形もあなたも変更 → diff 確認'],
        keep: ['保持', '著者データ領域 → 対象外']
      }.freeze

      def display_plan(plan)
        return if plan.empty?

        Common.log_always('📋 更新計画:')
        order = %i[add add_empty update conflict keep]
        plan.sort_by { [order.index(it.status), it.relative] }.each do |item|
          label, note = STATUS_LABELS.fetch(item.status)
          Common.log_always(format('   %s   %-42s（%s）', label, item.relative, note))
        end
      end

      def finish_dry_run(actionable)
        counts = actionable.group_by(&:status).transform_values(&:size)
        Common.log_always('')
        Common.log_always("--dry-run のため適用しません（追加 #{counts.values_at(:add, :add_empty).compact.sum} 件・更新 #{counts[:update] || 0} 件・競合 #{counts[:conflict] || 0} 件）")
        0
      end

      # 追加・更新の一括適用と、競合の個別確認を行う。
      # @return [Array(Array<PlanItem>, Array<PlanItem>, String?), Array(nil, nil, nil)]
      #   applied / skipped / バックアップ先（全体確認で中止した場合は applied が nil）
      def apply_plan(cmd, plan, scaffold_digests)
        adds      = plan.select { %i[add add_empty].include?(it.status) }
        updates   = plan.select { it.status == :update }
        conflicts = plan.select { it.status == :conflict }
        applied = []
        skipped = []
        backup_dir = nil

        # --- Phase: 追加＋更新（全体確認は 1 回。--yes でスキップ） ---
        if (adds.any? || updates.any?) && !cmd.options[:yes]
          answer = prompt("適用しますか？ 追加 #{adds.size} 件・更新 #{updates.size} 件 [y/N]: ")
          unless answer == 'y'
            Common.log_always('中止しました（ファイルは変更していません）。')
            return [nil, nil, nil]
          end
        end

        adds.each do |item|
          FileUtils.mkdir_p(File.dirname(item.relative))
          if item.status == :add_empty
            File.write(item.relative, EMPTY_DICTIONARY_TEMPLATES.fetch(item.relative), encoding: 'utf-8')
          else
            FileUtils.cp(File.join(scaffold_source, item.relative), item.relative)
          end
          applied << item
        end

        updates.each do |item|
          backup_dir = backup!(item.relative, backup_dir)
          FileUtils.cp(File.join(scaffold_source, item.relative), item.relative)
          applied << item
        end

        # --- Phase: 競合の個別確認（--yes でも必ず確認する） ---
        conflicts.each do |item|
          if confirm_conflict?(item.relative)
            backup_dir = backup!(item.relative, backup_dir)
            FileUtils.cp(File.join(scaffold_source, item.relative), item.relative)
            applied << item
          else
            skipped << item
            Common.log_always("   スキップ: #{item.relative}（次回の upgrade でもう一度確認できます）")
          end
        end

        [applied, skipped, backup_dir]
      end

      # 競合ファイルの diff を提示して適用可否を尋ねる（y/n/d ループ）
      def confirm_conflict?(relative)
        Common.log_always('')
        Common.log_always("   競合 #{relative}:")
        diff = unified_diff(File.join(scaffold_source, relative), relative)
        print_diff(diff, limit: DIFF_PREVIEW_LINES)

        loop do
          case prompt('   適用しますか？ [y]適用 / [n]スキップ / [d]diff 全文: ')
          in 'y' then return true
          in 'd' then print_diff(diff, limit: nil)
          else return false
          end
        end
      end

      def prompt(message)
        $stdout.print(message)
        $stdout.flush
        $stdin.gets&.strip.to_s.downcase
      end

      # 上書き対象の現物を .cache/vs/upgrade-backup/<timestamp>/ へツリー構造のまま退避する
      # @return [String] バックアップディレクトリ（初回呼び出しで作成）
      def backup!(relative, backup_dir)
        backup_dir ||= File.join(Common.cache_dir, 'upgrade-backup', Time.now.strftime('%Y%m%d-%H%M%S'))
        destination = File.join(backup_dir, relative)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(relative, destination)
        backup_dir
      end

      # 適用結果を lock へ反映する。
      # - 適用済み・最新・著者データ: 現在の雛形ハッシュを記録
      # - スキップ（競合で n）: 旧ハッシュのまま → 次回また競合として確認できる
      # - 雛形から消えたファイルのエントリは除去（「保持」扱いで比較対象外のため）
      def record_lock!(scaffold_digests, lock, applied:)
        old_files = lock&.dig(:files) || {}
        applied_set = applied.map(&:relative)

        files = scaffold_digests.filter_map do |relative, scaffold_digest|
          recorded =
            if ScaffoldLock.author_data?(relative) || applied_set.include?(relative)
              scaffold_digest
            elsif File.exist?(relative) && ScaffoldLock.file_digest(relative) == scaffold_digest
              scaffold_digest # 最新（lock なしプロジェクトの初回記録を含む）
            else
              old_files[relative] # スキップ・未適用は展開時点のまま
            end
          recorded && [relative, recorded]
        end.to_h

        ScaffoldLock.write('.', version: VivlioStarter::VERSION, files:)
      end

      def print_summary(plan, applied, skipped, backup_dir)
        add_count    = applied.count { %i[add add_empty].include?(it.status) }
        update_count = applied.count { %i[update conflict].include?(it.status) }
        message = "アップグレード完了: 追加 #{add_count}・更新 #{update_count}・スキップ #{skipped.size}"
        message += "（バックアップ: #{backup_dir}/）" if backup_dir
        Common.log_result(message, status: :success)

        keep_count = plan.count { it.status == :keep }
        Common.log_always("   保持 #{keep_count} 件（著者データ領域は変更していません）") if keep_count.positive?
        Common.log_always('   git 管理下です。git diff で差分確認、git checkout で巻き戻しできます。') if Dir.exist?('.git')
      end

      # ================================================================
      # 簡易 unified diff（外部 diff コマンド・追加 gem なし）
      # 共通プレフィックス/サフィックスを除いた中間部を LCS で比較する。
      # 中間部が大きすぎる場合は全置換表示にフォールバックする。
      # ================================================================

      LCS_LIMIT = 2_000

      # @return [Array<String>] "+" "-" " " prefix 付きの表示行
      def unified_diff(new_path, current_path)
        new_text     = File.read(new_path, encoding: 'utf-8')
        current_text = File.read(current_path, encoding: 'utf-8')
        return ['   （バイナリファイルのため diff を表示できません）'] unless new_text.valid_encoding? && current_text.valid_encoding?

        old_lines = current_text.lines.map(&:chomp)
        new_lines = new_text.lines.map(&:chomp)

        # --- Phase: 共通プレフィックス/サフィックスの切り出し ---
        prefix = 0
        prefix += 1 while prefix < old_lines.size && prefix < new_lines.size && old_lines[prefix] == new_lines[prefix]
        suffix = 0
        while suffix < old_lines.size - prefix && suffix < new_lines.size - prefix &&
              old_lines[-1 - suffix] == new_lines[-1 - suffix]
          suffix += 1
        end
        old_mid = old_lines[prefix...(old_lines.size - suffix)]
        new_mid = new_lines[prefix...(new_lines.size - suffix)]

        # --- Phase: 中間部の diff（大きすぎる場合は全置換にフォールバック） ---
        ops =
          if old_mid.size > LCS_LIMIT || new_mid.size > LCS_LIMIT
            old_mid.map { ['-', it] } + new_mid.map { ['+', it] }
          else
            lcs_diff(old_mid, new_mid)
          end

        render_hunks(old_lines, prefix, ops)
      end

      # LCS（最長共通部分列）による行単位 diff
      # @return [Array<Array(String, String)>] [記号, 行] の列（記号は ' ' '-' '+'）
      def lcs_diff(old_lines, new_lines)
        table = Array.new(old_lines.size + 1) { Array.new(new_lines.size + 1, 0) }
        old_lines.each_index do |i|
          new_lines.each_index do |j|
            table[i + 1][j + 1] =
              old_lines[i] == new_lines[j] ? table[i][j] + 1 : [table[i][j + 1], table[i + 1][j]].max
          end
        end

        ops = []
        i = old_lines.size
        j = new_lines.size
        while i.positive? || j.positive?
          if i.positive? && j.positive? && old_lines[i - 1] == new_lines[j - 1]
            ops.unshift([' ', old_lines[i -= 1]])
            j -= 1
          elsif j.positive? && (i.zero? || table[i][j - 1] >= table[i - 1][j])
            ops.unshift(['+', new_lines[j -= 1]])
          else
            ops.unshift(['-', old_lines[i -= 1]])
          end
        end
        ops
      end

      CONTEXT_LINES = 2

      # ops（中間部）を、前後 CONTEXT_LINES 行の文脈付き表示行に整形する
      def render_hunks(old_lines, prefix, ops)
        lines = []
        context_before = old_lines[[prefix - CONTEXT_LINES, 0].max...prefix] || []
        lines << "   @@ #{prefix + 1} 行目付近 @@"
        context_before.each { lines << "    #{it}" }
        ops.each do |mark, line|
          lines << (mark == ' ' ? "    #{line}" : "   #{mark}#{line}")
        end
        lines
      end

      def print_diff(diff, limit:)
        shown = limit ? diff.first(limit) : diff
        shown.each { Common.log_always(it) }
        Common.log_always("   … 残り #{diff.size - limit} 行（[d] で全文表示）") if limit && diff.size > limit
      end
    end
  end
end
