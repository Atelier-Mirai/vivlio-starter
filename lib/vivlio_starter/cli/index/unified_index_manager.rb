# frozen_string_literal: true

# ================================================================
# Class: UnifiedIndexManager
# ----------------------------------------------------------------
# 責務:
#   索引・用語集生成プロセス全体を統括するマネージャー
#   仕様書 index_glossary_spec.md に準拠
#
# 主要メソッド:
#   - auto_process!: 全自動候補抽出 → _index_glossary_review.md 生成
#   - apply_markdown_review!: Markdownから承認・リジェクトを適用
#   - build_index!: 索引ページを生成（内部用）
#   - build_glossary!: 用語集ページを生成（内部用）
# ================================================================

require_relative '../common'
require_relative 'unified_terms_manager'
require_relative 'review_queue_manager'
require_relative 'review_markdown_generator'
require_relative 'index_candidate_extractor'
require_relative 'index_match_scanner'
require_relative 'code_block_stripper'
require_relative 'unified_page_builder'
require_relative 'yomi_inferrer'

module VivlioStarter
  module CLI
    # IndexCommands モジュール内のクラスへのエイリアス
    IndexCandidateExtractor = IndexCommands::IndexCandidateExtractor
    IndexMatchScanner = IndexCommands::IndexMatchScanner
    CodeBlockStripper = IndexCommands::CodeBlockStripper
    UnifiedPageBuilder = IndexCommands::UnifiedPageBuilder
    YomiInferrer = IndexCommands::YomiInferrer

    class UnifiedIndexManager
      # R9: [用語]（読みなし）記法で ASCII 可視文字のみ 2 文字以下の語は登録しない。
      # 単位 [eV] [Hz] やフラグ解説 [g] が索引語として誤登録されるのを防ぐ
      # （[g] は pattern /\bg\b/ となり本文中の英字 g 全部にタグが付く）。
      # 意図的に登録したい場合は読み付き [eV|いーぶい] を使う。
      ASCII_SHORT_TERM_PATTERN = /\A[\x21-\x7E]{1,2}\z/

      attr_reader :terms_manager, :queue_manager, :markdown_generator

      def initialize
        @terms_manager = UnifiedTermsManager.new
        @queue_manager = ReviewQueueManager.new
        @markdown_generator = ReviewMarkdownGenerator.new
        @config = load_index_config
        @glossary_config = load_glossary_config
      end

      # 全自動索引候補抽出 → _index_review.md 生成
      # @param chapters [Array<String>] 対象章のリスト
      def auto_process!(chapters)
        auto_threshold = @config[:auto_approve_threshold] || 300
        review_threshold = @config[:review_threshold] || 150
        high_ratio = @config[:high_candidates_ratio] || 0.25
        auto_discovery = @config.fetch(:auto_discovery, true)

        Common.log_action('索引の自動処理を開始します...')

        # R8: 辞書へ書いた登録内容を種別ごとに集め、既定ログレベルで要約表示する
        dictionary_writes = {}

        # 1. 手動マークアップを検出して統合辞書に登録
        manual_terms = extract_manual_markup_terms(chapters)
        if manual_terms.any?
          added = @terms_manager.merge_terms!(manual_terms, flags: 'i', source: 'manual_markup')
          dictionary_writes['手動マークアップ'] = added if added.any?
          Common.log_info("手動マークアップから #{manual_terms.size} 件の用語を登録しました")
        end

        # auto_discovery が無効の場合、自動候補抽出をスキップ
        unless auto_discovery
          @terms_manager.record_scanned_chapters!(chapters)
          report_dictionary_writes(dictionary_writes)
          Common.log_info('auto_discovery: false のため、自動候補抽出をスキップします')
          Common.log_info('手動マークアップ [用語|読み] のみが索引に反映されます')
          return
        end

        # 2. 候補抽出
        candidates = extract_candidates(chapters)
        Common.log_info("候補抽出: #{candidates.size}件")

        # 3. 既存の承認済み用語（索引＋用語集）とリジェクト済み用語を除外
        existing_terms = @terms_manager.term_names
        rejected_terms = @queue_manager.load_rejected_terms
        rejected_count_in_candidates = 0

        filtered_candidates = candidates.reject do |c|
          term = c['term']
          if existing_terms.include?(term)
            true
          elsif rejected_terms.include?(term)
            rejected_count_in_candidates += 1
            true
          else
            false
          end
        end

        # 4. 高スコア候補を自動承認
        auto_approved = filtered_candidates
                        .select { |c| c['score'] >= auto_threshold }
                        .map { |candidate| normalize_candidate(candidate) }
        if auto_approved.any?
          added = @terms_manager.merge_terms!(auto_approved, flags: 'i', source: 'auto_extracted')
          dictionary_writes['自動承認'] = added if added.any?
        end

        # 5. 中スコア候補をHigh/Lowに分割
        review_candidates = filtered_candidates
                            .select { |c| c['score'] >= review_threshold && c['score'] < auto_threshold }
                            .map { |candidate| normalize_candidate(candidate).merge('is_new' => true) }

        high_candidates, low_candidates = split_candidates_by_ratio(review_candidates, high_ratio)

        # 6. 登録済み用語（索引＋用語集すべて）に文脈を付与
        terms_with_context = enrich_terms_with_context(@terms_manager.load_terms, chapters)

        # 7. リジェクト済み用語に文脈とスコアを付与
        # candidatesからスコアを復元できるように渡す
        rejected_with_context = enrich_rejected_with_context(candidates)

        # 8. _index_review.md を生成
        @markdown_generator.generate!(
          terms: terms_with_context,
          high_candidates: high_candidates,
          low_candidates: low_candidates,
          rejected: rejected_with_context
        )

        # 9. 走査した章集合を辞書へ記録（R7: ビルド時の章追加検知に使う）
        @terms_manager.record_scanned_chapters!(chapters)

        # 10. 結果レポート
        report_dictionary_writes(dictionary_writes)
        report_auto_results(auto_approved, high_candidates, low_candidates, auto_threshold, review_threshold,
                            rejected_count_in_candidates)
      end

      # Markdownから承認・リジェクトを適用
      # 仕様: vs index:apply は内部で vs index:build を実行しない
      def apply_markdown_review!
        unless @markdown_generator.exists?
          Common.log_warn('_index_glossary_review.md が見つかりません')
          Common.log_info('先に vs index:auto を実行してください')
          return
        end

        # --- Phase: 索引処理 ---
        index_approved = @markdown_generator.parse_index_approved
        index_rejected = @markdown_generator.parse_index_rejected

        # --- Phase: 用語集処理 ---
        glossary_approved = @markdown_generator.parse_glossary_approved
        glossary_rejected = @markdown_generator.parse_glossary_rejected

        # --- Phase: 共通処理 ---
        both_rejected = @markdown_generator.parse_rejected
        unreject = @markdown_generator.parse_unreject
        yomi_changes = @markdown_generator.parse_yomi_changes

        changes_made = false
        index_count = 0
        glossary_count = 0

        # --- Phase: 索引承認 ---
        if index_approved.any?
          @terms_manager.merge_terms!(index_approved, flags: 'i', source: 'auto_extracted')
          index_count = index_approved.size
          changes_made = true
        end

        # --- Phase: 用語集承認 ---
        if glossary_approved.any?
          validate_glossary_definitions!(glossary_approved)
          @terms_manager.merge_terms!(glossary_approved, flags: 'g', source: 'review')
          glossary_count = glossary_approved.size
          changes_made = true
        end

        # [ig] → [i] に変更された場合: g フラグを除去
        glossary_approved_names = glossary_approved.map { it['term'] }
        index_only = index_approved.reject { glossary_approved_names.include?(it['term']) }
        index_only.each do |term|
          next unless @terms_manager.glossary_term_names.include?(term['term'])

          @terms_manager.remove_flag!(term['term'], 'g')
          Common.log_info("用語集フラグを除去しました（索引のみ）: #{term['term']}")
          changes_made = true
        end

        # --- Phase: 索引のみリジェクト（[-i]） ---
        if index_rejected.any?
          index_rejected.each { @terms_manager.remove_flag!(it['term'], 'i') }
          @queue_manager.save_rejected_terms(index_rejected)
          changes_made = true
        end

        # --- Phase: 用語集のみリジェクト（[-g]） ---
        if glossary_rejected.any?
          glossary_rejected.each { @terms_manager.remove_flag!(it['term'], 'g') }
          @queue_manager.save_rejected_terms(glossary_rejected)
          changes_made = true
        end

        # --- Phase: 両方リジェクト（[r]） ---
        if both_rejected.any?
          both_rejected.each { @terms_manager.remove_term!(it['term']) }
          @queue_manager.save_rejected_terms(both_rejected)
          changes_made = true
        end

        # --- Phase: リジェクト解除 + 直接登録 ---
        if unreject.any?
          unreject.each do |entry|
            @queue_manager.unreject_term_by_name!(entry['term'])
            flag = entry['flag'] || 'i'
            term_data = { 'term' => entry['term'], 'yomi' => entry['yomi'] }
            flags = case flag
                    when 'i', 'x' then 'i'
                    when 'g' then 'g'
                    when 'ig', 'gi' then 'ig'
                    else 'i'
                    end
            @terms_manager.merge_terms!([term_data], flags:, source: 'unreject')
            index_count += 1 if flags.include?('i')
            glossary_count += 1 if flags.include?('g')
            Common.log_info("リジェクト解除 → [#{flag}] 登録: #{entry['term']}")
          end
          changes_made = true
        end

        # --- Phase: 読み変更 ---
        if yomi_changes.any?
          @terms_manager.update_yomi!(yomi_changes)
          changes_made = true
        end

        # --- Phase: 孤立データ除去 ---
        index_approved_names = index_approved.map { it['term'] }
        glossary_approved_names_all = glossary_approved.map { it['term'] }
        unreject_index_names = unreject.select { %w[i x ig gi].include?(it['flag']) }.map { it['term'] }
        unreject_glossary_names = unreject.select { %w[g ig gi].include?(it['flag']) }.map { it['term'] }

        # 明示的にリジェクトされた用語は孤立除去の対象外
        # （[-i] で i を除去した後に残る g を誤って除去しないため）
        explicitly_rejected = (index_rejected + glossary_rejected + both_rejected).map { it['term'] }.uniq

        # 索引フラグの孤立除去
        stale_index = @terms_manager.index_term_names - index_approved_names - unreject_index_names - explicitly_rejected
        stale_index.each do |term_name|
          @terms_manager.remove_flag!(term_name, 'i')
          Common.log_info("索引フラグを除去: #{term_name}")
          changes_made = true
        end

        # 用語集フラグの孤立除去
        stale_glossary = @terms_manager.glossary_term_names - glossary_approved_names_all - unreject_glossary_names - explicitly_rejected
        stale_glossary.each do |term_name|
          @terms_manager.remove_flag!(term_name, 'g')
          Common.log_info("用語集フラグを除去: #{term_name}")
          changes_made = true
        end

        # --- Phase: Section 4 同期処理 ---
        rejected_section_all = @markdown_generator.parse_rejected_section_all
        unreject_names = unreject.map { it['term'] }

        confirmed_rejected = rejected_section_all.select { ['', ' '].include?(it['flag']) }
                                                 .reject { unreject_names.include?(it['term']) }

        if confirmed_rejected.any?
          rejected_count = 0
          confirmed_rejected.each do |entry|
            term_name = entry['term']
            next unless @terms_manager.term_names.include?(term_name)

            @terms_manager.remove_term!(term_name)
            Common.log_info("除外済みリストに基づき登録を解除: #{term_name}")
            rejected_count += 1
          end

          @queue_manager.save_rejected_terms(confirmed_rejected)
          changes_made = true if rejected_count.positive? || confirmed_rejected.any?
        end

        if changes_made
          rejected_total = both_rejected.size + (confirmed_rejected&.size || 0)
          Common.log_success("索引: #{index_count}件、用語集: #{glossary_count}件、リジェクト: #{rejected_total}件")
          Common.log_info("読み変更: #{yomi_changes.size}件") if yomi_changes.any?
          Common.log_success('index_glossary_terms.yml を更新しました')
          Common.log_info('ページ生成は vs build 実行時に行われます')
        else
          Common.log_warn('変更がありませんでした')
          Common.log_info('_index_glossary_review.md でフラグを編集してください')
        end

        # _index_glossary_review.md は残す（再編集の可能性があるため）
        # vs build の clean 処理で削除される
        changes_made
      end

      # 用語集の説明文バリデーション
      # require_definition: true の場合、説明文が空ならエラー
      # max_definition_length を超過している場合は警告
      def validate_glossary_definitions!(terms)
        max_length = @glossary_config[:max_definition_length] || 200

        # 説明文の長さチェック（Markdown装飾を除去した文字数）
        terms.each do |term|
          definition = term['definition'].to_s
          next if definition.strip.empty?

          plain_text = strip_markdown(definition)
          next unless plain_text.length > max_length

          Common.log_warn(
            "用語「#{term['term']}」の説明文が #{max_length} 文字を超過しています " \
            "(#{plain_text.length} 文字)"
          )
        end

        return unless @glossary_config[:require_definition]

        missing = terms.select { it['definition'].to_s.strip.empty? }
        return if missing.empty?

        missing.each do |term|
          Common.log_error("用語「#{term['term']}」に説明文がありません")
        end
        raise "用語集の説明文が必須ですが、#{missing.size}件の用語に説明文がありません"
      end

      # Markdown装飾を除去してプレーンテキストを取得
      def strip_markdown(text)
        text
          .gsub(/\*\*(.+?)\*\*/, '\1')  # **bold**
          .gsub(/\*(.+?)\*/, '\1')      # *italic*
          .gsub(/`(.+?)`/, '\1')        # `code`
          .gsub(/\[(.+?)\]\(.+?\)/, '\1') # [link](url)
          .gsub(/^#+\s*/, '')           # # heading
          .gsub(/^\s*[-*]\s+/, '')      # - list item
          .gsub(/\n+/, ' ')             # newlines to space
          .strip
      end

      # 索引・用語集ページを生成（内部用 - vs build から呼ばれる）
      # @param chapters [Array<String>] 対象章のリスト
      def build_index!(chapters)
        Common.log_action('索引・用語集ページを生成しています...')

        # 本文スキャン（索引タグ付け＋用語集リンク生成）
        scanner = IndexMatchScanner.new(defer_warnings: true)
        scanner.scan_all_chapters!(chapters, read_only: false)

        # UnifiedPageBuilder で索引＋用語集を生成
        builder = UnifiedPageBuilder.new(glossary_config: @glossary_config)

        # 索引ページ生成
        builder.build_index!

        # 用語集ページ生成（glossary_enabled かつ g フラグの用語がある場合）
        # スキャンは辞書を書かない（R1）ためリロード不要
        if glossary_enabled?
          glossary = @terms_manager.glossary_terms
          builder.build_glossary!(glossary)
          warn_unmatched_glossary_terms(glossary, scanner.glossary_backlinks, chapters)
        end

        Common.log_success('索引・用語集ページの生成が完了しました')

        # R7: 索引候補の抽出（vs index:auto）が未実施の章を検出して案内
        warn_unscanned_chapters(chapters)

        return unless scanner.config_missing || scanner.no_matches

        IndexCommands.add_post_build_message(IndexCommands::INDEX_TERMS_MISSING_MESSAGE)
      end

      # 用語集ページを生成（後方互換 - 単独呼び出し用）
      def build_glossary!
        return unless glossary_enabled?

        @terms_manager.clear_cache!
        glossary = @terms_manager.glossary_terms
        builder = UnifiedPageBuilder.new(glossary_config: @glossary_config)
        result = builder.build_glossary!(glossary)
        Common.log_success('用語集ページを生成しました') if result
      end

      # 用語集機能が有効か
      def glossary_enabled?
        @glossary_config[:enabled] == true
      end

      # R7: ビルド対象のうち index:auto が未走査の章があれば、ビルド末尾の案内へ積む。
      # 旧辞書（scanned_chapters キーなし）では判定しない——誤警告を避けるため
      # @param chapters [Array<String>] ビルド対象章
      def warn_unscanned_chapters(chapters)
        scanned = @terms_manager.scanned_chapters
        return if scanned.nil?

        unscanned = chapters.map { File.basename(it.to_s, '.md') } - scanned
        return if unscanned.empty?

        IndexCommands.add_post_build_message(
          "🟡 索引候補の抽出が未実施の章があります: #{unscanned.join(', ')} → vs index:auto を実行してください"
        )
      end

      # R4: ビルド対象章に 1 回も出現しない用語集語を警告する（掲載自体は維持）。
      # catalog 外の章に出現があるならその章名を添え、どこにも無ければその旨を伝える。
      # 除外したい場合の判断（-g フラグ）は著者に委ねる——定義は書籍の語彙資産のため。
      # @param glossary_terms [Array<Hash>] 用語集対象の用語
      # @param glossary_backlinks [Hash{String => Array}] 今回のスキャンで出現した語 → 出現箇所
      # @param chapters [Array<String>] ビルド対象章
      def warn_unmatched_glossary_terms(glossary_terms, glossary_backlinks, chapters)
        missing = glossary_terms.reject { glossary_backlinks.key?(it['term']) }
        return if missing.empty?

        build_targets = chapters.map { File.basename(it.to_s, '.md') }
        all_contents = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).to_h do |path|
          [File.basename(path, '.md'), File.read(path, encoding: 'utf-8')]
        end

        missing.each do |term|
          name = term['term']
          found = all_contents.keys.select { all_contents[it].include?(name) }
          outside = found - build_targets
          hint = if outside.any?
                   "catalog 外の #{outside.join(', ')} に出現"
                 elsif found.any?
                   "#{found.join(', ')} に文字列出現はあるがリンク化されていません（コード内・タグ内等）"
                 else
                   '原稿のどこにも出現しません（語の変更・削除？）'
                 end
          Common.log_warn("用語集語がビルド対象章に出現しません: #{name}（#{hint}）")
        end
      end

      # リジェクト済み候補の一覧表示
      def list_rejected_terms
        @queue_manager.list_rejected_terms
      end

      # リジェクト解除
      # @param term_or_number [String] 用語名または番号
      def unreject_term!(term_or_number)
        @queue_manager.unreject_term!(term_or_number)
      end

      # リジェクト履歴をクリア
      def reset_rejected!
        @queue_manager.reset_rejected!
      end

      private

      # 候補の文脈を正規化
      def normalize_candidate(candidate)
        candidate.merge('contexts' => deduplicate_contexts(candidate['contexts']))
      end

      def deduplicate_contexts(contexts)
        return [] unless contexts&.any?

        seen = {}
        contexts.each_with_object([]) do |ctx, result|
          chapter = ctx['chapter'] || ctx[:chapter] || 'unknown'
          context_text = ctx['context'] || ctx[:context] || ''
          key = "#{chapter}|#{context_text}"
          next if seen[key]

          seen[key] = true
          result << { 'chapter' => chapter, 'context' => context_text }
        end
      end

      # 設定を読み込み
      # 共通設定（index_glossary）と個別設定（index）をマージ
      # @return [Hash] index設定
      def load_index_config
        load_shared_config.merge(Common::CONFIG.index.to_h)
      end

      # glossary設定を読み込み
      # 共通設定（index_glossary）と個別設定（glossary）をマージ
      # @return [Hash] glossary設定
      def load_glossary_config
        load_shared_config.merge(Common::CONFIG.glossary.to_h)
      end

      # 共通設定（index_glossary）を読み込み
      # @return [Hash] 共通設定
      def load_shared_config
        Common::CONFIG.index_glossary.to_h
      end

      # 手動マークアップ用語を抽出
      # @param chapters [Array<String>] 対象章のリスト（ベースネームまたはフルパス）
      # @return [Array<Hash>] 手動マークアップ用語のリスト
      def extract_manual_markup_terms(chapters)
        terms = []
        yomi_inferrer = YomiInferrer.new
        # R9 でスキップした語 → 出現章のリスト（章ごとに 1 回だけ警告するため集約）
        skipped_short_terms = Hash.new { |h, k| h[k] = [] }

        chapters.each do |chapter|
          # ベースネームの場合はフルパスに変換
          chapter_path = resolve_chapter_path(chapter)
          next unless chapter_path && File.exist?(chapter_path)

          content = File.read(chapter_path, encoding: 'utf-8')
          # コード（フェンス／インライン）を除外してから索引記法を拾う。
          # 素朴な /```...```/ は地の文中のインライン ``` でフェンス対がズレ、
          # コード例の [###] や [00, 90-98, 99] を誤検出するため状態機械方式を使う。
          content_without_code = CodeBlockStripper.strip(content)
          chapter_name = File.basename(chapter_path, '.*')

          # [用語|読み] 形式を検出（コードフェンス除外済みコンテンツから）
          content_without_code.scan(/\[([^\]|]+)\|([^\]]+)\]/) do |term, yomi|
            next if term.nil? || term.empty?

            context = extract_surrounding_context(content, term)
            terms << {
              'term' => term.strip,
              'yomi' => yomi.strip,
              'contexts' => [{ 'chapter' => chapter_name, 'context' => context }]
            }
          end

          # [用語] 形式を検出（読みなし、コードフェンス除外済み）
          # (?!\() で画像記法 ![alt](url) の alt 部分は既に除外済み
          content_without_code.scan(/\[([^\]|]+)\](?!\()/) do |match|
            term = match[0]
            next if term.nil? || term.empty?
            next if term.match?(/^https?:/) # URL を除外
            next if term.match?(/^\^/) # 脚注参照 [^1] を除外

            # R9: 単位・記号表記（[eV] [Hz] [g] 等）は登録せず、集約して後で警告
            if term.match?(ASCII_SHORT_TERM_PATTERN)
              skipped_short_terms[term] << chapter_name
              next
            end

            yomi = yomi_inferrer.available? ? yomi_inferrer.infer(term) : term
            context = extract_surrounding_context(content, term)
            terms << {
              'term' => term.strip,
              'yomi' => yomi,
              'contexts' => [{ 'chapter' => chapter_name, 'context' => context }]
            }
          end

          # [|] や [||] など、パイプ文字のみで構成される用語を検出
          content_without_code.scan(/\[(\|+)\]/) do |match|
            term = match[0]
            context = extract_surrounding_context(content, term)
            terms << {
              'term' => term,
              'yomi' => term,
              'contexts' => [{ 'chapter' => chapter_name, 'context' => context }]
            }
          end
        end

        warn_skipped_short_terms(skipped_short_terms)

        # 重複を除去
        terms.uniq { |t| t['term'] }
      end

      # R9 でスキップした短い ASCII 語を警告する（警告親切方針: before→after ＋出現箇所）
      # @param skipped [Hash{String => Array<String>}] 語 → 出現章のリスト
      def warn_skipped_short_terms(skipped)
        skipped.each do |term, chapter_names|
          Common.log_warn(
            "[#{term}] は単位・記号表記とみなし索引登録しません（#{chapter_names.uniq.join(', ')}）",
            detail: "索引に載せる場合は読み付きで [#{term}|よみ] と書いてください"
          )
        end
      end

      # 候補を抽出
      # @param chapters [Array<String>] 対象章のリスト
      # @return [Array<Hash>] 候補のリスト
      def extract_candidates(chapters)
        extractor = IndexCandidateExtractor.new
        extractor.extract_from_chapters!(chapters)

        # 読み推測用
        yomi_inferrer = YomiInferrer.new

        # 既存用語の読みを取得（学習済みの読みを優先するため）
        existing_yomi = @terms_manager.load_terms.to_h { |t| [t['term'], t['yomi']] }

        extractor.all_candidates.filter_map do |term|
          # ゴミ用語をフィルタリング
          next nil if garbage_term?(term)

          # 既存の読みを優先、なければ推測
          yomi = existing_yomi[term] || (yomi_inferrer.available? ? yomi_inferrer.infer(term) : term)

          contexts = extractor.term_contexts[term] || []
          normalized_contexts = contexts.map do |ctx|
            {
              'chapter' => ctx[:chapter] || ctx['chapter'],
              'context' => smart_context_cut(ctx[:context] || ctx['context'])
            }
          end

          {
            'term' => term,
            'yomi' => yomi,
            'score' => extractor.term_scores[term] || 0,
            'contexts' => normalized_contexts
          }
        end
      end

      # 候補をHigh/Lowに分割（仕様書 5.1.1 に準拠）
      # @param candidates [Array<Hash>] 候補のリスト
      # @param high_ratio [Float] High候補の割合（既定: 0.25）
      # @return [Array<Array<Hash>>] [high_candidates, low_candidates]
      def split_candidates_by_ratio(candidates, high_ratio)
        return [[], []] if candidates.empty?

        # スコア降順でソート
        sorted = candidates.sort_by { |c| -(c['score'] || 0) }

        # 基準位置を算出（切り上げ）
        base_index = (sorted.size * high_ratio).ceil
        base_index = [base_index, 1].max # 最低1件はHighに

        # 境界スコアを決定
        boundary_score = sorted[[base_index - 1, sorted.size - 1].min]['score'] || 0

        # 同スコアは全てHighに含める
        high = sorted.select { |c| (c['score'] || 0) >= boundary_score }
        low = sorted.select { |c| (c['score'] || 0) < boundary_score }

        [high, low]
      end

      # 登録済み用語に文脈と用語集登録状態を付与
      # R5: 原稿推敲に追従するため、現原稿に無い context を捨て、空になったら複数章ぶん補充する
      # （温存条件は context_live? に集約・R6）
      # @param terms [Array<Hash>] 用語のリスト
      # @param chapters [Array<String>] 対象章のリスト
      # @return [Array<Hash>] 文脈付き用語のリスト
      def enrich_terms_with_context(terms, chapters)
        loaded_contents = load_squashed_chapter_contents(chapters)

        terms.map do |term|
          enriched = term.dup
          flags = term['flags'].to_s

          # flags に基づいて索引・用語集の登録状態を反映
          enriched['in_index'] = flags.include?('i')
          enriched['in_glossary'] = flags.include?('g')

          # stale な context を捨て、空になったら本文から補充
          fresh = Array(enriched['contexts']).select { context_live?(it, loaded_contents) }
          fresh = collect_contexts_for_term(term['term'], chapters) if fresh.empty?
          enriched['contexts'] = annotate_out_of_scope_contexts(fresh, loaded_contents)

          enriched
        end
      end

      # リジェクト済み用語に文脈とスコアを付与
      # @param candidates [Array<Hash>] 現在の候補リスト（スコア復元用）
      # @return [Array<Hash>] 文脈付きリジェクト用語のリスト
      def enrich_rejected_with_context(candidates = [])
        rejected = @queue_manager.load_rejected_terms_with_metadata
        chapters = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))

        rejected.map do |item|
          enriched = item.dup

          # スコアがない場合は候補リストから復元を試みる
          unless enriched['score']
            candidate = candidates.find { it['term'] == item['term'] }
            enriched['score'] = candidate['score'] if candidate&.dig('score')
          end

          # 文脈がない場合は本文から抽出
          enriched['contexts'] = collect_contexts_for_term(item['term'], chapters) unless enriched['contexts']&.any?

          enriched
        end
      end

      # context の収集上限（章数）。候補抽出側（IndexCandidateExtractor）の蓄積数
      # `.first(3)` と揃える——レビュー表示は先頭 2 件のためこれで十分
      MAX_CONTEXT_CHAPTERS = 3

      # 用語の文脈を全対象章から収集する（出現する章ごとに 1 件・上限 MAX_CONTEXT_CHAPTERS）
      # 最初の 1 章で打ち切ると複数章で使われる語の使用例が 1 件に痩せるため（報告書 §5.1）
      # @param term [String] 用語
      # @param chapters [Array<String>] 対象章のリスト（ベースネームまたはフルパス）
      # @return [Array<Hash>] 文脈情報のリスト
      def collect_contexts_for_term(term, chapters)
        contexts = []
        chapters.each do |chapter|
          # ベースネームの場合はフルパスに変換
          chapter_path = resolve_chapter_path(chapter)
          next unless chapter_path && File.exist?(chapter_path)

          content = File.read(chapter_path, encoding: 'utf-8')
          next unless content.include?(term)

          context = extract_surrounding_context(content, term)
          next if context.to_s.empty?

          contexts << { 'chapter' => File.basename(chapter_path, '.*'), 'context' => context }
          break if contexts.size >= MAX_CONTEXT_CHAPTERS
        end
        contexts
      end

      # context が現原稿に生存しているかを判定する（stale 判定の 1 実装・§4.3）。
      # YAML 折返し等の空白の揺れを無視するため、両者から全空白を除去して部分一致で見る。
      # 参照章が今回読み込んだ集合に無い場合:
      #   - contents/ 等に実在する章なら判定せず温存（R6: catalog 外・部分実行を壊さない）
      #   - どこにも実在しない章（削除・改名）なら stale として捨てる
      # @param ctx [Hash] 文脈情報（'chapter'/'context'）
      # @param loaded_contents [Hash{String => String}] 今回読み込んだ章 → 空白除去済み本文
      # @return [Boolean]
      def context_live?(ctx, loaded_contents)
        chapter = ctx['chapter'] || ctx[:chapter]
        text = (ctx['context'] || ctx[:context]).to_s.gsub(/[[:space:]]+/, '')
        return false if chapter.nil? || text.empty?

        return !resolve_chapter_path(chapter).nil? unless loaded_contents.key?(chapter)

        loaded_contents[chapter].include?(text)
      end

      # 今回読み込む章の本文を全空白除去済みで用意する（context_live? の下準備）
      # @param chapters [Array<String>] 対象章のリスト
      # @return [Hash{String => String}] 章ベースネーム → 空白除去済み本文
      def load_squashed_chapter_contents(chapters)
        chapters.each_with_object({}) do |chapter, result|
          path = resolve_chapter_path(chapter)
          next unless path && File.exist?(path)

          result[File.basename(path, '.*')] = File.read(path, encoding: 'utf-8').gsub(/[[:space:]]+/, '')
        end
      end

      # 今回対象外の章を参照する context に表示用マークを付ける（判断材料の誤解防止・§4.3-4）。
      # レビュー md の表示にのみ使われ、apply のパース時に注記は剥がされるため辞書へは戻らない
      # @param contexts [Array<Hash>] 文脈情報のリスト
      # @param loaded_contents [Hash{String => String}] 今回読み込んだ章の集合
      # @return [Array<Hash>]
      def annotate_out_of_scope_contexts(contexts, loaded_contents)
        contexts.map do |ctx|
          chapter = ctx['chapter'] || ctx[:chapter]
          loaded_contents.key?(chapter) ? ctx : ctx.merge('out_of_scope' => true)
        end
      end

      # 章のパスを解決（ベースネーム → フルパス）
      # @param chapter [String] 章名またはパス
      # @return [String, nil] ファイルパス
      def resolve_chapter_path(chapter)
        return chapter if File.exist?(chapter)

        # contents/ → ワークスペース（前処理済み中間 .md・P4 §3.4-1）の順で探す
        possible_paths = [
          File.join(Common::CONTENTS_DIR, "#{chapter}.md"),
          File.join(Common::BUILD_HTML_DIR, "#{chapter}.md")
        ]

        possible_paths.find { |path| File.exist?(path) }
      end

      # 用語の周辺文脈を抽出
      # @param content [String] 本文
      # @param term [String] 用語
      # @return [String] 文脈
      def extract_surrounding_context(content, term)
        context_width = @config[:context_width] || 40
        index = content.index(term)
        return '' unless index

        # 基本の範囲を計算
        ideal_start = index - context_width
        ideal_end = index + term.length + context_width

        # 前方が足りない場合は後方を延長
        if ideal_start.negative?
          shortage = -ideal_start
          ideal_end += shortage
          ideal_start = 0
        end

        # 後方が足りない場合は前方を延長
        if ideal_end > content.length
          shortage = ideal_end - content.length
          ideal_start = [ideal_start - shortage, 0].max
          ideal_end = content.length
        end

        raw_context = content[ideal_start...ideal_end]
        smart_context_cut(raw_context)
      end

      # スマートな文脈カット（先頭と末尾の両方で形態素境界を考慮）
      # @param text [String] テキスト
      # @return [String] カット後のテキスト
      def smart_context_cut(text)
        return '' if text.nil? || text.empty?

        # 改行を除去
        cleaned = text.to_s.gsub(/[\r\n]+/, ' ').strip

        smart_cutting = @config[:smart_context_cutting]
        smart_cutting = true if smart_cutting.nil?

        # 先頭が単語の途中（小文字カナなど）で始まっている場合、常に修正
        # これは長さに関係なく適用
        start_offset = skip_partial_word_start(cleaned)
        cleaned = cleaned[start_offset..] if start_offset.positive?

        context_width = @config[:context_width] || 40
        max_length = context_width * 2

        return cleaned if cleaned.length <= max_length
        return cleaned[0...max_length] unless smart_cutting

        # 先頭のカット: 文頭でない場合、適切な区切り位置から開始
        start_pos = find_smart_start_position(cleaned, max_length)

        # 先頭をカットした後のテキスト
        working_text = cleaned[start_pos..]

        return working_text if working_text.length <= max_length

        # 末尾のカット
        find_smart_end_position(working_text, max_length)
      end

      # スマートな開始位置を探す
      # @param text [String] テキスト
      # @param max_length [Integer] 最大長
      # @return [Integer] 開始位置
      def find_smart_start_position(text, max_length)
        return 0 if text.length <= max_length

        # 先頭が単語の途中（小文字カナなど）で始まっている場合、次の単語境界まで進める
        start_offset = skip_partial_word_start(text)
        return start_offset if start_offset.positive?

        # 先頭20文字以内で区切りを探す
        search_range = text[0..19]

        # 優先度順: 句読点 > スペース > 助詞
        boundary_patterns = [
          /[。、！？]/, # 句読点
          /\s+/, # スペース
          /[をはがのにでとへやもって]/ # 助詞・助動詞
        ]

        boundary_patterns.each do |pattern|
          match = search_range.index(pattern)
          next unless match&.positive? && match < 18

          # マッチの次の位置から開始
          return match + 1
        end

        0
      end

      # 単語の途中で始まっている場合、次の単語開始位置まで進める
      # @param text [String] テキスト
      # @return [Integer] スキップすべき文字数
      def skip_partial_word_start(text)
        return 0 if text.nil? || text.empty?

        first_char = text[0]

        # 1. 小文字カナ（単語の途中でしか現れない文字）で始まる場合
        return find_next_word_boundary(text) if first_char.match?(/[ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ]/)

        # 2. カタカナで始まり、後続もカタカナが続く場合（単語の途中の可能性）
        #    例: "ブサイト" は "ウェブサイト" の途中
        if first_char.match?(/[ァ-ヴー]/) && text.length > 1
          # 連続するカタカナの終端を探す
          katakana_end = find_katakana_sequence_end(text)
          if katakana_end.positive?
            # カタカナ列の後ろに、文字種の境界があればそこから開始
            return katakana_end
          end
        end

        0
      end

      # 次の単語境界を探す
      # @param text [String] テキスト
      # @return [Integer] 境界位置
      def find_next_word_boundary(text)
        # 最大15文字まで探索
        (1..[text.length - 1, 15].min).each do |i|
          char = text[i]
          # 文字種の変化点を探す（カタカナ→非カタカナ、ひらがな→漢字など）
          return i if word_boundary_char?(char)
        end
        0
      end

      # カタカナ列の終端位置を探す
      # @param text [String] テキスト
      # @return [Integer] カタカナ列の終端位置（0なら単語境界なし）
      def find_katakana_sequence_end(text)
        # 最大10文字のカタカナ列を探索
        (1..[text.length - 1, 10].min).each do |i|
          char = text[i]
          # カタカナでなくなったら、そこが境界
          return i unless char.match?(/[ァ-ヴー]/)
        end
        0
      end

      # 単語境界になりうる文字かどうか
      # @param char [String] 文字
      # @return [Boolean]
      def word_boundary_char?(char)
        return false if char.nil?

        # 漢字、句読点、スペース、英数字の開始
        char.match?(/[一-龯。、！？\s「」『』（）a-zA-Z0-9]/)
      end

      # スマートな終了位置を探す
      # @param text [String] テキスト
      # @param max_length [Integer] 最大長
      # @return [String] カット後のテキスト
      def find_smart_end_position(text, max_length)
        # 末尾付近で区切りを探す
        truncated = text[0..(max_length + 10)]

        boundary_patterns = [
          /[。、！？]/,
          /\s+/,
          /[をはがのにでとへやもって]/
        ]

        boundary_patterns.each do |pattern|
          last_match = truncated.rindex(pattern)
          next unless last_match && last_match > max_length - 15 && last_match <= max_length + 5

          return truncated[0..last_match]
        end

        text[0...max_length]
      end

      # 索引候補として除外すべき用語かどうかを判定
      # @param term_text [String] 用語テキスト
      # @return [Boolean] 除外すべきならtrue
      def garbage_term?(term_text)
        return true if term_text.nil? || term_text.empty?

        # Markdown太字記法の一部
        return true if term_text.start_with?('**') || term_text.end_with?('**')

        # カラーコード (#e74c3c, '#e74c3c' など)
        return true if term_text.match?(/^['"]?#[0-9a-fA-F]{3,8}['"]?$/)
        return true if term_text.match?(/^['"]?#[0-9a-fA-F]{3,8}['"]?,\s*['"]?#/)

        # 数字のみ
        return true if term_text.match?(/^\d+$/)

        false
      end

      # R8: auto_process! が辞書へ書いた登録内容を既定ログレベルで必ず表示する。
      # 何も登録しなかった実行では無言（無言＝無変更が成立する）。
      # @param dictionary_writes [Hash{String => Array<String>}] 登録種別 → 追加された語名
      def report_dictionary_writes(dictionary_writes)
        return if dictionary_writes.empty?

        summary = dictionary_writes.map { |kind, names| "#{kind} #{names.size} 語（#{names.join(', ')}）" }.join('・')
        Common.log_always("📝 辞書を更新しました: #{summary}")
      end

      # 結果をレポート（auto_process!用）
      # 総括行（候補数・レビューファイル案内）は既定ログレベルで表示する（R8）
      def report_auto_results(auto_approved, high_candidates, low_candidates, auto_threshold, review_threshold,
                              rejected_count)
        Common.log_summary(
          "候補抽出完了: 自動承認 #{auto_approved.size} 件（スコア≥#{auto_threshold}）・" \
          "推奨候補 #{high_candidates.size} 件・一般候補 #{low_candidates.size} 件" \
          "（#{review_threshold}≤スコア<#{auto_threshold}）",
          detail: "#{ReviewMarkdownGenerator::REVIEW_FILE} を編集後、vs index:apply を実行してください"
        )

        Common.log_info("リジェクト設定により #{rejected_count} 件の候補を除外しました") if rejected_count.positive?
      end
    end
  end
end
