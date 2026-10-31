# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/upgrade.rb
# ================================================================
# 責務:
#   執筆環境をまとめて最新化する（`vs upgrade` のドメイン層）。三段構成:
#   ① vivlio-starter 本体の gem 更新（新版があれば確認のうえ gem update →
#      新しい版の vs で自分を再起動して続きを実行）
#   ② プロジェクトの雛形追従（project-upgrade-command-spec.md）と、仕上げの
#      Gemfile.lock 追随（lock が古い版を指したままだと bundler 経由の実行が止まる）
#   ③ 外部ツールの一括更新（DoctorCommands::ToolUpgrader へ委譲）
#   ①を最初に行うのは、古い gem の雛形で②を済ませると本体更新後にもう一度
#   upgrade が必要になるため。②を③より先に行うのは、対話（競合確認）を
#   前半へ集め、時間のかかる brew/npm 更新を無人で流せるようにするため
#   （upgrade-unification-spec.md）。
#
# 雛形追従の仕組み（三者比較）:
#   config/scaffold.lock（展開時の雛形ハッシュ）・現在の雛形・プロジェクト現物の
#   3 点から各ファイルを 追加/更新/競合/最新 に分類する。
#   - 追加: 雛形の新規ファイル → コピー
#   - 更新: 雛形が改良・著者は未変更 → 自動適用可（--yes で無確認）
#   - 合流: 雛形も著者も変更したが**別の場所** → 3-way マージで両立（尋ねない）
#   - 競合: 雛形も著者も**同じ場所**を変更 → diff 提示・個別確認（y/n/d）
#   - 著者データ領域（ScaffoldLock::AUTHOR_DATA_*）は分類しない。雛形で上書きせず、計画にも載せない
#
#   合流の共通祖先は ScaffoldBase が調達する（upgrade-three-way-merge-spec.md）。
#   祖先が得られないファイルは従来どおり競合として著者に尋ねる。
#
# 安全策:
#   - 上書き前に必ず .cache/vs/upgrade-backup/<timestamp>/ へ元ファイルを退避
#   - --dry-run はファイルシステムに一切書き込まない（lock 含む）
#   - プロジェクト外（config/book.yml なし）では雛形追従だけをスキップし、
#     本体更新・ツール更新は実行できる
# ================================================================

require 'fileutils'

require_relative 'scaffold_lock'
require_relative 'scaffold_base'
require_relative 'scaffold_updates'
require_relative 'config_keys'
require_relative 'retired_key_remover'
require_relative 'token_resolver'
require_relative 'index/unified_terms_manager'
require_relative 'new'
require_relative 'doctor'
require_relative '../version'

module VivlioStarter
  module CLI
    module UpgradeCommands
      extend self

      # 計画表の 1 行。status: :add / :add_empty / :update / :merge / :conflict / :tidy
      #
      # merged      … :merge のときだけ入る、3-way マージ後の中身
      # overlapping … :conflict のうち「祖先が取れたうえで衝突した」＝双方が
      #               本当に同じ場所を変えたもの。適用すれば著者の変更が消えるので、
      #               そう名指しできる（祖先が取れなかった競合では断定できない）
      # 雛形追従の結果。aborted は全体の確認で「いいえ」と答えたとき（以後の書き換えもしない）
      SyncResult = Data.define(:code, :new_keys, :aborted) do
        def initialize(code: 0, new_keys: nil, aborted: false) = super
      end

      # 著者データの整理の計画。book_text は計画を立てたときの book.yml の中身
      TidyPlan = Data.define(:book_text, :retired, :orphans, :pages, :new_keys) do
        def book_yml? = retired.any? || new_keys&.added&.any?
        def empty? = paths.empty?

        # 整理で書き換えるファイル
        def paths
          [(File.join('config', 'book.yml') if book_yml?),
           (UnifiedTermsManager::UNIFIED_FILE if orphans.any?),
           *pages].compact
        end
      end

      PlanItem = Data.define(:relative, :status, :merged, :overlapping) do
        def initialize(merged: nil, overlapping: false, **) = super
      end

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
        File.join('config', 'spellcheck_allowlist.yml') => <<~YAML,
          # スペルチェックで「綴り誤り」と指摘したくない語を並べます
          # 1 行 1 語。`vs lint --register` を実行すると、未知だった語がここへ追加されます
          []
        YAML
        File.join('config', 'textlint_allowlist.yml') => <<~YAML
          # textlint-filter-rule-allowlist で使用する除外語句リスト
          # 書籍名、資格名称、専門用語など、プロジェクト固有の除外対象を記載します
          # 正規表現も使用可能（例: "/pattern/flags"）
          []
        YAML
      }.freeze

      # 改名した設定ファイル（旧名 → 新名）。著者が編集するファイルなので、
      # 名前を変えただけでは**中身ごと読まれなくなる**——登録した表記ゆれルールや
      # 許可語が黙って効かなくなるため、雛形追従の前に移し替える。
      #
      # `textlint_prh.yml` は v0.14.0（2025-11-04）から配っており、ベータ版
      # （2026-04-26）の利用者の手元にもある。`user_words.txt` はベータの
      # 2 か月後（2026-06-30）の実装なので既存プロジェクトには無いが、
      # 開発中の本のために同じ経路で拾っておく。
      RENAMED_CONFIG_FILES = {
        File.join('config', 'textlint_prh.yml') => File.join('config', 'textlint_rewrite.yml'),
        File.join('config', 'user_words.txt') => File.join('config', 'spellcheck_allowlist.yml')
      }.freeze

      # 改名に伴って中身の参照も書き換えるファイル（著者が編集する設定）
      RENAMED_REFERENCES = {
        File.join('config', '.textlintrc.yml') => { './textlint_prh.yml' => './textlint_rewrite.yml' }
      }.freeze

      DIFF_PREVIEW_LINES = 20

      GEMFILE_LOCK = 'Gemfile.lock'

      # Gemfile.lock が固定している vivlio-starter の版を拾う。specs 節と CHECKSUMS 節に
      # 同じ綴りで現れるので先頭の 1 つだけ見る（DEPENDENCIES 節には括弧が付かない）。
      LOCKED_SELF_VERSION = /^\s+vivlio-starter \((\d[^)]*)\)/

      # 比較元の雛形ディレクトリ。テストではフィクスチャ雛形に差し替える（DI）。
      attr_writer :scaffold_source

      def scaffold_source = @scaffold_source || NewCommands::SCAFFOLD_SOURCE

      # ツール更新フェーズと自己更新の外部依存（テストで差し替える DI）
      attr_writer :tool_deps

      def tool_deps = @tool_deps || DoctorCommands::ToolUpgrader.default_deps

      # Samovar `UpgradeCommand` から呼び出すメイン処理（終了コードを返す）。
      # ①本体 gem 更新 → ②雛形追従 → ③外部ツール更新 の順に実行する（順序の理由は
      # ファイル冒頭コメント参照）。①で更新が走った場合は exec で新しい版に置き換わる
      # ため、②③は新しい版の vs が実行する。
      def run_from_command(cmd)
        options = cmd.options

        # --- Phase: ① 本体 gem 更新（--skip-self-update は再起動ループ防止も兼ねる）---
        self_result = options[:skip_self_update] ? :none : self_update!(options, tool_deps)

        # --- Phase: ② 雛形追従＋Gemfile.lock の追随（プロジェクト外はスキップ——③は場所を問わず有用）---
        sync = SyncResult.new
        if gem_repository?
          Common.log_always('💡 vivlio-starter の開発リポジトリのため、雛形の追従はスキップします（書籍プロジェクトの直下で実行すると適用できます）。')
        elsif File.exist?(File.join('config', 'book.yml'))
          sync = sync_scaffold!(cmd)
          refresh_gemfile_lock!(options) unless sync.aborted
        else
          Common.log_always('💡 書籍プロジェクト外のため、雛形の追従はスキップします（プロジェクト直下で再実行すると適用できます）。')
        end

        # --- Phase: ③ 外部ツール更新 ---
        tools_code = DoctorCommands::ToolUpgrader.run!(
          { yes: options[:yes], dry_run: options[:dry_run], verbose: options[:verbose] },
          deps: tool_deps
        )

        # --- Phase: 足した設定の案内（③の長い出力で流れないよう、いちばん最後に出す）---
        ScaffoldUpdates.report_new_book_keys(sync.new_keys, scaffold_source:, dry_run: options[:dry_run])

        [self_result == :failed ? 1 : 0, sync.code, tools_code].max
      end

      # gem 自身のリポジトリか。ここにも config/book.yml（本書の原稿の設定）があるので、
      # book.yml だけで判断すると書籍プロジェクトと取り違える。scaffold.lock が無いため差分が
      # すべて競合になり、[y] で gem 開発用の Gemfile・README.md が雛形のものに置き換わる
      def gem_repository? = File.exist?('vivlio-starter.gemspec')

      # 本体 gem の自己更新。新版があれば確認のうえ gem update し、新しい版の vs で
      # 同じ upgrade を再実行する（relaunch! で exec に置き換わり、戻ってこない）。
      # 更新失敗は警告して現在の版のまま続行——雛形追従・ツール更新の価値は残るため。
      # @return [Symbol] :none（新版なし）/ :skipped（案内のみ）/ :failed（更新失敗）
      def self_update!(options, deps, current: VivlioStarter::VERSION)
        latest = DoctorCommands::ToolUpgrader.latest_gem_version(deps, 'vivlio-starter')
        return :none unless latest && Gem::Version.correct?(current) &&
                            Gem::Version.new(latest) > Gem::Version.new(current)

        if options[:dry_run]
          Common.log_always("📣 vivlio-starter #{latest} が公開されています（現在 #{current}）。--dry-run のため更新しません。")
          return :skipped
        end
        unless options[:yes] || confirm_self_update?(latest, current, deps)
          Common.log_always("本体の更新をスキップしました（手動更新: gem update vivlio-starter）。今回は現在の版（#{current}）の雛形で続行します。")
          return :skipped
        end

        Common.log_always("⬆️  vivlio-starter を #{current} → #{latest} に更新しています…")
        unless DoctorCommands::ToolUpgrader.run_gem_command('gem update vivlio-starter', deps)
          Common.log_warn('vivlio-starter の更新に失敗しました。現在の版のまま続行します（手動更新: gem update vivlio-starter）。')
          return :failed
        end

        Common.log_always("🔁 vivlio-starter #{latest} で続きを実行します…")
        relaunch!(options)
      end

      # --- Phase: 分類（三者比較）以降の雛形追従フェーズ ---
      def sync_scaffold!(cmd)
        # --- Phase: 改名の追随（雛形と比べる前に済ませる） ---
        follow_renames!(dry_run: cmd.options[:dry_run])

        # --- Phase: 分類（三者比較） ---
        Common.log_summary("雛形との差分を確認しています…（gem #{VivlioStarter::VERSION} の雛形）")
        scaffold_digests = ScaffoldLock.digest_scaffold(scaffold_source)
        lock = ScaffoldLock.read
        warn_missing_lock if lock.nil?
        tidy = plan_tidy(lock)
        plan = with_tidy_rows(build_plan(scaffold_digests, lock), tidy)

        # --- Phase: 計画表示（著者データの整理も、確認の前に見せる） ---
        display_plan(plan, tidy_details(tidy))
        if plan.empty?
          Common.log_result('プロジェクトは雛形の最新状態です。', status: :success)
          save_lock_and_base!(scaffold_digests, lock, applied: []) unless cmd.options[:dry_run]
          return SyncResult.new(new_keys: tidy.new_keys)
        end
        if cmd.options[:dry_run]
          finish_dry_run(plan)
          return SyncResult.new(new_keys: tidy.new_keys)
        end

        # --- Phase: 適用（追加・更新・合流 → 競合の個別確認） ---
        applied, skipped, backup_dir = apply_plan(cmd, plan, scaffold_digests)
        return SyncResult.new(aborted: true) if applied.nil? # 全体確認で中止

        # --- Phase: lock・基準の更新 → 著者データの整理 → 完了報告 ---
        save_lock_and_base!(scaffold_digests, lock, applied:, skipped:)
        backup_dir, new_keys = apply_tidy(tidy, lock, backup_dir)
        print_summary(plan, applied, skipped, backup_dir)
        SyncResult.new(new_keys:)
      end

      private

      # Gemfile.lock が指す vivlio-starter を、いま動いている版へ合わせる。
      #
      # upgrade の仕事は「プロジェクトを新しい版に合わせること」なので、雛形だけ進めて
      # lock を置き去りにすると半端に終わる。置き去りの lock は、著者が `bundle exec vs`
      # や `bundle install` を使う場面で「その版が無い」と言って止まる——古い版が yank
      # 済みの prerelease だと、ネットワークがあっても解決できない（実例: rc.2 は
      # 2026-08-22 に yank 済み）。
      #
      # 確認は求めない。触るのは生成物である lock だけで、入るのはプロジェクトが
      # すでに Gemfile で宣言している gem である。upgrade を打った時点で意思は足りている。
      def refresh_gemfile_lock!(options)
        return unless File.exist?(GEMFILE_LOCK)

        locked = locked_self_version
        return if locked.nil? || locked == Gem::Version.new(VivlioStarter::VERSION)

        if options[:dry_run]
          Common.log_always("📣 Gemfile.lock は #{locked} を指しています（現在 #{VivlioStarter::VERSION}）。--dry-run のため更新しません。")
          return
        end

        Common.log_always("⬆️  Gemfile.lock を追随させています（#{locked} → #{VivlioStarter::VERSION}）…")
        if DoctorCommands::ToolUpgrader.run_gem_command('bundle update vivlio-starter', tool_deps)
          Common.log_result("Gemfile.lock を #{VivlioStarter::VERSION} に合わせました。", status: :success)
        else
          Common.log_warn('Gemfile.lock の更新に失敗しました。手元で bundle update vivlio-starter を実行してください' \
                          '（vs コマンド自体は lock を見ないため、このままでも執筆は続けられます）。')
        end
      end

      # 古い版から持ち越した著者データを、今の版に合わせて片づける計画（改善案.md #114）。
      #   - book.yml の廃止キー（読まれないのに、どのコマンドでも警告が出続ける）
      #   - 雛形で増えた book.yml のキー（scaffold-update-notice-spec.md §10）
      #   - 原稿の無い章を指す索引辞書の main:（ベータ版の雛形が配った本書の辞書の名残など）
      #   - contents/ に残った、今の版では使わない特別ページ
      #
      # 雛形追従と違い、著者データ領域に手を入れる。だから計画の表に載せ、同じ確認に含める。
      # 確認の後に整理すると、何が変わるのかを知らないまま答えることになり、「いいえ」と
      # 答えてもファイルが書き換わる。
      def plan_tidy(lock)
        book_text = File.read(File.join('config', 'book.yml'), encoding: 'utf-8')
        TidyPlan.new(book_text:,
                     retired: RetiredKeyRemover.authored(book_text, ConfigKeys::RETIRED.keys),
                     orphans: UnifiedTermsManager.new.orphan_main_references,
                     pages: stale_system_pages,
                     new_keys: ScaffoldUpdates.plan_new_book_keys(lock, scaffold_source:))
      end

      # 整理で書き換えるファイルを計画の行にする
      def with_tidy_rows(plan, tidy) = plan + tidy.paths.map { PlanItem.new(relative: it, status: :tidy) }

      # 確認の後で整理を実行する。失う設定は無いので、退避を取って何をしたかを示す。
      # @return [Array(String?, BookKeyInserter::Result?)] バックアップ先と、足した設定の結果
      def apply_tidy(tidy, lock, backup_dir)
        return [backup_dir, tidy.new_keys] if tidy.empty?

        # --- Phase: book.yml の廃止キー（移した先のあるキーは移し、ほかは消す） ---
        book_yml = File.join('config', 'book.yml')
        if tidy.retired.any?
          moved, removed = tidy.retired.partition { moved_key_target(it) }
          rewritten = moved.reduce(tidy.book_text) do |text, path|
            text && RetiredKeyRemover.move(text, path, moved_key_target(path))
          end
          rewritten = RetiredKeyRemover.remove(rewritten, removed) if rewritten && removed.any?
          if rewritten
            backup_dir = backup!(book_yml, backup_dir)
            File.write(book_yml, rewritten, encoding: 'utf-8')
          else
            todo = moved.map { "#{it.join('.')} を #{moved_key_target(it).join('.')} へ移し" } +
                   removed.map { "#{it.join('.')} を消し" }
            Common.log_warn("#{book_yml} の廃止キーを自動で直せませんでした（書き方を読み取れない）",
                            detail: "#{todo.join('、')}てください")
          end
        end

        # --- Phase: 雛形で増えたキー（廃止キーを整理した後の中身へ差し込む） ---
        new_keys, backup_dir = add_new_book_keys!(lock, backup_dir)

        # --- Phase: 索引辞書の main: ---
        if tidy.orphans.any?
          backup_dir = backup!(UnifiedTermsManager::UNIFIED_FILE, backup_dir)
          UnifiedTermsManager.new.forget_missing_chapters!
        end

        # --- Phase: 使われなくなった特別ページ ---
        tidy.pages.each do |page|
          backup_dir = backup!(page, backup_dir)
          FileUtils.rm(page)
        end

        Common.log_result("整理しました（バックアップ: #{backup_dir}/）", status: :success) if backup_dir
        [backup_dir, new_keys]
      end

      # 雛形で増えたキーを book.yml へ足す（scaffold-update-notice-spec.md §10）。
      # @return [Array(BookKeyInserter::Result?, String?)] 知らせに使う結果と、バックアップ先
      def add_new_book_keys!(lock, backup_dir)
        plan = ScaffoldUpdates.plan_new_book_keys(lock, scaffold_source:)
        return [plan, backup_dir] if plan.nil? || plan.added.empty?

        book_yml = File.join('config', 'book.yml')
        backup_dir = backup!(book_yml, backup_dir)
        File.write(book_yml, plan.text, encoding: 'utf-8')
        [plan, backup_dir]
      end

      # contents/ に残った扉・免責・奥付・部扉の原稿（改善案.md #114）。
      #
      # 古い版はこれらを contents/ に置いていたが、今の版はビルドのたびに book.yml から
      # .cache/vs/ に作り直し、contents/ のものは読まない（TokenResolver::Resolver）。
      # 残っていると、著者が直しても紙面が変わらず戸惑うので、退避して消す。
      # 消しても紙面は変わらない。`_README.md` など、ほかの `_` で始まるファイルは触らない。
      # @return [Array<String>] プロジェクト直下からの相対パス
      def stale_system_pages
        Dir.glob(File.join(Common::CONTENTS_DIR, '_*.md')).select do |path|
          name = File.basename(path, '.md')
          TokenResolver::Resolver::CACHED_SYSTEM_FILES.include?(name) || name.match?(/\A_part\d+\z/)
        end.sort
      end

      # 値を別のキーへ移した廃止キーなら、移した先のパス（multivolume-spec.md §3.5）
      # @param path [Array<String>] 例: ["output", "cover"]
      # @return [Array<String>, nil] 例: ["book", "cover"]
      def moved_key_target(path)
        ConfigKeys.moves[path.map(&:to_sym)]&.map(&:to_s)
      end

      # 移す廃止キーの知らせ。移した先がすでに書かれていれば、そちらを残すので、値が違えば両方を示す
      # @param written [Hash] 書き換える前の book.yml
      def moved_key_details(from, to, written)
        old_value = written.dig(*from)
        return ["#{from.join('.')} を #{to.join('.')} へ移します（#{old_value}）"] unless written.dig(*to[0...-1])&.key?(to.last)

        kept = written.dig(*to)
        lines = ["#{to.join('.')} がすでにあるので、#{from.join('.')} の行を削除します"]
        lines << "#{to.join('.')}: #{kept} を残し、#{from.join('.')}: #{old_value} を削除します" unless kept == old_value
        lines
      end

      # 整理の行の下に並べる詳細（ファイルごと）。著者データに手を入れるので、確認の前に見せる
      # @return [Hash{String => Array<String>}]
      def tidy_details(tidy)
        details = { File.join('config', 'book.yml') => book_yml_details(tidy) }
        if tidy.orphans.any?
          chapters = tidy.orphans.values.flatten.uniq
          listed = chapters.first(3).join('・') + (chapters.size > 3 ? " ほか #{chapters.size - 3} 章" : '')
          details[UnifiedTermsManager::UNIFIED_FILE] = ["原稿の無い章（#{listed}）を指す主要参照を外します（#{tidy.orphans.size} 語）",
                                                        '外した語は、次の vs index:auto が主要参照の候補を出します']
        end
        tidy.pages.each { details[it] = ['今の版では使わないので削除します（扉・免責・奥付は book.yml から作ります）'] }
        details
      end

      def book_yml_details(tidy)
        moved, removed = tidy.retired.partition { moved_key_target(it) }
        written = moved.any? ? (YAML.safe_load(tidy.book_text, aliases: true) || {}) : {}
        lines = moved.flat_map { moved_key_details(it, moved_key_target(it), written) }
        lines << "廃止キーを削除します（#{removed.map { it.join('.') }.join('・')}）" if removed.any?

        added = tidy.new_keys&.added.to_a
        lines << "新しい設定キーを追加します（#{added.first}#{" ほか #{added.size - 1} 件" if added.size > 1}）" if added.any?
        lines
      end

      # @return [Gem::Version, nil] lock が読めない・自分の行が無い・版が壊れていれば nil
      def locked_self_version
        found = File.read(GEMFILE_LOCK, encoding: 'utf-8')[LOCKED_SELF_VERSION, 1]
        found && Gem::Version.correct?(found) ? Gem::Version.new(found) : nil
      rescue StandardError
        nil
      end

      # 旧名の設定ファイルを新名へ移し、参照している設定の中身も書き換える。
      # 新名が既にあるなら触らない（著者が手で移した後の再実行を壊さない）。
      def follow_renames!(dry_run:)
        moved = RENAMED_CONFIG_FILES.select do |old, new|
          File.exist?(old) && !File.exist?(new)
        end
        rewrites = RENAMED_REFERENCES.select do |path, pairs|
          File.exist?(path) && pairs.any? { |from, _| File.read(path, encoding: 'utf-8').include?(from) }
        end
        return if moved.empty? && rewrites.empty?

        moved.each { |old, new| report_rename(old, new, dry_run) }
        rewrites.each_key { Common.log_action("設定の参照を更新します: #{it}") }
        return if dry_run

        moved.each { |old, new| FileUtils.mv(old, new) }
        rewrites.each do |path, pairs|
          body = File.read(path, encoding: 'utf-8')
          pairs.each { |from, to| body = body.gsub(from, to) }
          File.write(path, body, encoding: 'utf-8')
        end
      end

      def report_rename(old, new, dry_run)
        prefix = dry_run ? '[dry-run] ' : ''
        Common.log_action("#{prefix}設定ファイルを改名します: #{old} → #{new}")
      end

      def warn_missing_lock
        Common.log_warn('scaffold.lock が見つかりません（本機能導入前のプロジェクト）。現物と雛形を直接比較し、差分のあるファイルは安全側に倒してすべて「競合」として確認します。')
      end

      # 雛形の全ファイルを §1.2 の表にしたがって分類する
      # @param scaffold_digests [Hash{String => String}] 現在の雛形のハッシュ表
      # @param lock [Hash, nil] ScaffoldLock.read の結果
      # @return [Array<PlanItem>] :latest（表示不要）は含まない
      def build_plan(scaffold_digests, lock)
        lock_files = lock&.dig(:files) || {}
        roots = ScaffoldBase.ancestor_roots

        scaffold_digests.filter_map do |relative, scaffold_digest|
          status =
            if ScaffoldLock.author_data?(relative)
              classify_author_data(relative)
            else
              ScaffoldLock.classify(relative, scaffold_digest, lock_files)
            end
          next if status.nil? || status == :latest

          if status == :conflict
            plan_for_conflict(relative, lock_files[relative], roots)
          else
            PlanItem.new(relative:, status:)
          end
        end
      end

      # 競合と分類されたファイルを 3-way マージにかける。祖先が取れて衝突なく
      # 合流できたなら :merge（尋ねない）、そうでなければ従来どおり :conflict。
      def plan_for_conflict(relative, lock_digest, roots)
        base = ScaffoldBase.ancestor_path(relative, lock_digest, roots)
        return PlanItem.new(relative:, status: :conflict) if base.nil?

        merged = ScaffoldBase.merge(base, relative, File.join(scaffold_source, relative))
        return PlanItem.new(relative:, status: :merge, merged:) if merged

        PlanItem.new(relative:, status: :conflict, overlapping: true)
      end

      # 著者データ領域の分類。雛形で上書きしないので、計画に載せるのは足りない辞書だけ。
      # 雛形に同じ名前のファイル（contents/99-postface.md）があっても、中身は関係が無い
      # @return [Symbol, nil] :add_empty / nil（表示不要）
      def classify_author_data(relative)
        :add_empty if !File.exist?(relative) && EMPTY_DICTIONARY_TEMPLATES.key?(relative)
      end

      STATUS_LABELS = {
        add: ['追加', '雛形の新規ファイル'],
        add_empty: ['追加', '著者辞書が無いため空の辞書を用意'],
        update: ['更新', '雛形が改良・著者は未変更 → 自動適用可'],
        merge: ['合流', '雛形も著者も変更・別の場所 → 自動で両立'],
        conflict: ['競合', '雛形も著者も同じ場所を変更 → diff 確認'],
        tidy: ['整理', nil]
      }.freeze

      # 整理の詳細を、行の真下に並べるときの字下げ
      PLAN_DETAIL_INDENT = ' ' * 12

      # @param details [Hash{String => Array<String>}] 行の下に並べる詳細
      def display_plan(plan, details)
        return if plan.empty?

        Common.log_always('📋 更新計画:')
        order = %i[add add_empty update merge conflict tidy]
        plan.sort_by { [order.index(it.status), it.relative] }.each do |item|
          label, note = STATUS_LABELS.fetch(item.status)
          row = note ? format('   %s   %-42s（%s）', label, item.relative, note) : "   #{label}   #{item.relative}"
          Common.log_always(row)
          details.fetch(item.relative, []).each { Common.log_always("#{PLAN_DETAIL_INDENT}#{it}") }
        end
      end

      def finish_dry_run(actionable)
        counts = actionable.group_by(&:status).transform_values(&:size)
        Common.log_always('')
        merged = counts[:merge] || 0
        message = "--dry-run のため適用しません（追加 #{counts.values_at(:add, :add_empty).compact.sum} 件" \
                  "・更新 #{counts[:update] || 0} 件"
        message += "・合流 #{merged} 件" if merged.positive?
        message += "・競合 #{counts[:conflict] || 0} 件"
        message += "・整理 #{counts[:tidy]} 件" if counts[:tidy]
        Common.log_always("#{message}）")
      end

      # 追加・更新の一括適用と、競合の個別確認を行う。
      # @return [Array(Array<PlanItem>, Array<PlanItem>, String?), Array(nil, nil, nil)]
      #   applied / skipped / バックアップ先（全体確認で中止した場合は applied が nil）
      def apply_plan(cmd, plan, scaffold_digests)
        adds      = plan.select { %i[add add_empty].include?(it.status) }
        updates   = plan.select { it.status == :update }
        merges    = plan.select { it.status == :merge }
        conflicts = plan.select { it.status == :conflict }
        tidied    = plan.select { it.status == :tidy }
        applied = []
        skipped = []
        backup_dir = nil

        # --- Phase: 追加＋更新＋合流（全体確認は 1 回。--yes でスキップ） ---
        if (adds.any? || updates.any? || merges.any? || tidied.any?) && !cmd.options[:yes]
          unless Common.confirm?("適用しますか？ #{bulk_summary(adds, updates, merges, tidied)}")
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

        # 合流は雛形をコピーせず、マージ済みの中身を書く（著者の変更を残すため）。
        # 中身は分類の時点で確定しているので、ここで git を呼び直さない
        merges.each do |item|
          backup_dir = backup!(item.relative, backup_dir)
          File.binwrite(item.relative, item.merged)
          applied << item
        end

        # --- Phase: 競合の個別確認（--yes でも必ず確認する） ---
        conflicts.each do |item|
          if confirm_conflict?(item)
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

      # 全体確認の文言。合流は 0 件のことが多いので、あるときだけ足す
      def bulk_summary(adds, updates, merges, tidied)
        summary = "追加 #{adds.size} 件・更新 #{updates.size} 件"
        summary += "・合流 #{merges.size} 件" if merges.any?
        summary += "・整理 #{tidied.size} 件" if tidied.any?
        summary
      end

      # 競合ファイルの diff を提示して適用可否を尋ねる（y/n/d ループ）
      def confirm_conflict?(item)
        relative = item.relative
        Common.log_always('')
        Common.log_always("   競合 #{relative}:")
        # 3-way を通しても合流できなかった＝双方が同じ場所を変えている。
        # このときだけ「著者の変更が失われる」と断定できる（祖先が取れなかった
        # 競合では、そもそも双方が何を変えたのか分かっていない）
        Common.log_warn('雛形と著者が同じ場所を変えています。適用すると著者の変更は失われます。') if item.overlapping
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

      # 自己更新の最終確認。非対話（パイプ/CI）では安全側に倒して更新しない
      def confirm_self_update?(latest, current, deps)
        return false unless deps.stdin.tty?

        Common.confirm?("vivlio-starter を #{current} → #{latest} に更新しますか？", input: deps.stdin)
      end

      # 更新後の新しい gem の vs で同じ upgrade を続きから実行する（exec で置き換わる）。
      # --skip-self-update を付けて再帰を防ぐ。Bundler 配下だと exec 先が Gemfile に
      # 拘束されて新しい版を見られないため、素の環境で実行する。
      # $PROGRAM_NAME（RubyGems の binstub）は実行時に最新版へディスパッチする。
      def relaunch!(options)
        args = [$PROGRAM_NAME, 'upgrade', '--skip-self-update']
        args << '--yes' if options[:yes]
        defined?(Bundler) ? Bundler.with_unbundled_env { Kernel.exec(*args) } : Kernel.exec(*args)
      end

      # 上書き対象の現物を .cache/vs/upgrade-backup/<timestamp>/ へツリー構造のまま退避する
      # @return [String] バックアップディレクトリ（初回呼び出しで作成）
      def backup!(relative, backup_dir)
        backup_dir ||= File.join(Common.cache_dir, 'upgrade-backup', Time.now.strftime('%Y%m%d-%H%M%S'))
        destination = File.join(backup_dir, relative)
        FileUtils.mkdir_p(File.dirname(destination))
        # 同じ秒に 2 度退避すると、書き換えた後の中身で元を潰す。最初の中身を残す
        FileUtils.cp(relative, destination) unless File.exist?(destination)
        backup_dir
      end

      # 適用結果を lock へ反映する。
      # - 適用済み・最新・著者データ: 現在の雛形ハッシュを記録
      # - スキップ（競合で n）: 旧ハッシュのまま → 次回また競合として確認できる。
      #   断ったときの雛形のハッシュは declined に残す。残さないと、ビルドのたびに
      #   同じ 💡 が出続ける（scaffold-update-notice-spec.md §3.2）
      # - 雛形から消えたファイルのエントリは除去（比較対象外のため）
      def record_lock!(scaffold_digests, lock, applied:, skipped: [])
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

        ScaffoldLock.write('.', version: VivlioStarter::VERSION, files:,
                                book_keys: ScaffoldLock.scaffold_book_keys(scaffold_source),
                                declined: skipped.to_h { [it.relative, scaffold_digests.fetch(it.relative)] })
        files
      end

      # lock を更新し、同じ内容で次回の共通祖先（雛形の基準）を保管する。
      # **必ず lock と同時に**行う——基準だけが先に進むと、次回のマージが
      # 祖先＝新版となって雛形側の変更を黙って捨てる（ScaffoldBase 冒頭）。
      def save_lock_and_base!(scaffold_digests, lock, applied:, skipped: [])
        files = record_lock!(scaffold_digests, lock, applied:, skipped:)
        ScaffoldBase.sync!('.', scaffold_source:, lock_files: files)
      end

      def print_summary(plan, applied, skipped, backup_dir)
        add_count    = applied.count { %i[add add_empty].include?(it.status) }
        merge_count  = applied.count { it.status == :merge }
        update_count = applied.count { %i[update conflict].include?(it.status) }
        message = "アップグレード完了: 追加 #{add_count}・更新 #{update_count}"
        tidy_count   = plan.count { it.status == :tidy }
        message += "・合流 #{merge_count}" if merge_count.positive?
        message += "・整理 #{tidy_count}" if tidy_count.positive?
        message += "・スキップ #{skipped.size}"
        message += "（バックアップ: #{backup_dir}/）" if backup_dir
        Common.log_result(message, status: :success)

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

      # diff の凡例。`-` / `+` だけでは**どちらが自分のファイルか分からない**ため、
      # 記号の意味と「適用するとどうなるか」を毎回添える。実測で「gem 側が ○○ で
      # プロジェクト側が ×× ということが分からない」という声があった（2026-08-12）。
      # 標準の unified diff の `--- a/` `+++ b/` に相当する行だが、パスではなく
      # **役割**を書く——著者に必要なのはファイル名ではなく、どちらが残るかである。
      #
      # 行頭を「凡例」で始めるのは色付けの都合でもある。`   - …` で始めると
      # paint_diff_line が削除行と見なして赤く塗ってしまう
      DIFF_LEGEND = [
        '   凡例  - 著者の今のファイル  /  + 新しい雛形（適用すると + の側になります）'
      ].freeze

      # 表示上の 1 ハンク。start_lineno は旧ファイル（＝著者の現物）基準の 1 起点
      Hunk = Data.define(:start_lineno, :lines)

      # ops（中間部）を、ハンクに分けた表示行へ整形する（upgrade-conflict-review-spec.md §3(b)）
      def render_hunks(old_lines, prefix, ops)
        hunks = build_hunks(restore_full_ops(old_lines, prefix, ops))
        return ['   （差分はありません）'] if hunks.empty?

        lines = [diff_summary(hunks), *DIFF_LEGEND]
        hunks.each do |hunk|
          lines << "   @@ #{hunk.start_lineno} 行目付近 @@"
          hunk.lines.each { |mark, line| lines << (mark == ' ' ? "    #{line}" : "   #{mark}#{line}") }
        end
        lines
      end

      # ops（中間部）の前後に共通部分を戻し、ファイル全体の op 列へ復元する。
      # ハンク分割は「変更の周囲だけを切り出す」操作なので、中間部だけを見ていると
      # 先頭側の文脈（共通プレフィックスの末尾）が取れない
      def restore_full_ops(old_lines, prefix, ops)
        consumed = ops.count { |mark, _| mark != '+' }
        head = old_lines[0...prefix].map { [' ', it] }
        tail = (old_lines[(prefix + consumed)..] || []).map { [' ', it] }
        head + ops + tail
      end

      # 各グループを前後 CONTEXT_LINES 行ぶん広げてハンクにする
      def build_hunks(all_ops)
        group_change_indexes(all_ops).map do |group|
          first = [group.first - CONTEXT_LINES, 0].max
          last  = [group.last + CONTEXT_LINES, all_ops.size - 1].min
          Hunk.new(start_lineno: old_lineno_at(all_ops, first), lines: all_ops[first..last])
        end
      end

      # 変更行の添字を、隙間が文脈で埋まらないところで切ってまとめる。
      # 標準の unified diff と同じ規則で、間の無変更行が CONTEXT_LINES × 2 以下なら
      # 1 つのハンクに残す。これを怠ると最初の変更から最後の変更までが 1 塊になり、
      # 無変更行が肝心の変更をプレビュー外へ押し出す（2026-08-12 の事故の真因）
      def group_change_indexes(all_ops)
        changed = all_ops.each_index.select { all_ops[it].first != ' ' }
        changed.each_with_object([]) do |index, groups|
          if groups.empty? || index - groups.last.last > (CONTEXT_LINES * 2) + 1
            groups << [index]
          else
            groups.last << index
          end
        end
      end

      # all_ops の添字が旧ファイルの何行目にあたるか（1 起点）。
      # 追加行は旧ファイルに存在しないので行数を進めない
      def old_lineno_at(all_ops, index)
        1 + all_ops[0...index].count { |mark, _| mark != '+' }
      end

      # prompt の前に置く要約。`-` 行はすべて著者の現在の内容なので、
      # この数字はそのまま「適用すると失われる行数」でもある
      def diff_summary(hunks)
        added   = hunks.sum { it.lines.count { |mark, _| mark == '+' } }
        removed = hunks.sum { it.lines.count { |mark, _| mark == '-' } }
        "   変更 #{hunks.size} 箇所（+#{added} / -#{removed} 行）"
      end

      def print_diff(diff, limit:)
        enabled = diff_color_enabled?
        shown = limit ? diff.first(limit) : diff
        shown.each { Common.log_always(paint_diff_line(it, enabled:)) }
        return unless limit && diff.size > limit

        print_truncation_notice(diff.drop(limit), enabled)
      end

      # 切り詰めたときに何を言うかが、事故を止める最後の砦になる。
      # 「残り N 行」だけでは「読まなくてよい続き」と読めてしまい、実際に
      # 見ていない変更が y で承認された（2026-08-12 の実測）
      def print_truncation_notice(hidden, enabled)
        hunks = hidden.count { it.start_with?('   @@') }
        tail  = hunks.positive? ? "・未表示 #{hunks} 箇所" : ''
        Common.log_always(paint("   … 残り #{hidden.size} 行#{tail}（[d] で全文表示）", :dim, enabled:))
        # 隠れているのが文脈行だけなら、変更はすべて見えている。ここで警告を出すと
        # 狼少年になり、本当に変更が隠れている場面での警告まで軽く扱われる
        return if hidden.none? { ['-', '+'].include?(it[3]) }

        Common.log_always(paint('   🟡 [y] は表示していない箇所にも適用されます', :yellow, enabled:))
      end

      ANSI_CODES = { red: 31, green: 32, yellow: 33, cyan: 36, dim: 2 }.freeze

      def paint(text, color, enabled:)
        enabled ? "\e[#{ANSI_CODES.fetch(color)}m#{text}\e[0m" : text
      end

      # 表示行 1 本を色付けする。
      # 記号の判定に lstrip を使ってはならない——CSS のカスタムプロパティを含む
      # 文脈行（"    --preface-h3-marker: …"）が削除行に化ける。render_hunks は
      # 変更行を "   -…"、文脈行を "    …" と組み立てるので、添字 3 が記号そのものになる
      def paint_diff_line(line, enabled:)
        color = case line[3]
                when '-' then :red
                when '+' then :green
                when '@' then :cyan
                end
        color ? paint(line, color, enabled:) : line
      end

      # 色を付けてよい環境か。NO_COLOR（no-color.org の事実上の標準）と TERM=dumb を
      # 尊重し、パイプ/リダイレクト先には付けない。
      # 色は「diff の生成」ではなく「出力」の関心事なので、ここだけに閉じ込める——
      # unified_diff / render_hunks は素のテキストを返し続けるため、diff の中身を
      # 検査するテストが色の有無に影響されない
      def diff_color_enabled?(io = $stdout, env = ENV)
        return false unless io.tty?
        return false unless env.fetch('NO_COLOR', '').to_s.empty?

        env['TERM'] != 'dumb'
      end
    end
  end
end
