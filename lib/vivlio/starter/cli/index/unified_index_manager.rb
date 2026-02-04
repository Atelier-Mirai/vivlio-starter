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
require_relative 'index_terms_manager'
require_relative 'glossary_terms_manager'
require_relative 'review_queue_manager'
require_relative 'review_markdown_generator'
require_relative 'index_candidate_extractor'
require_relative 'index_match_scanner'
require_relative 'index_page_builder'
require_relative 'glossary_page_builder'
require_relative 'yomi_inferrer'

module Vivlio
  module Starter
    module CLI
      # IndexCommands モジュール内のクラスへのエイリアス
      IndexCandidateExtractor = IndexCommands::IndexCandidateExtractor
      IndexMatchScanner = IndexCommands::IndexMatchScanner
      IndexPageBuilder = IndexCommands::IndexPageBuilder
      YomiInferrer = IndexCommands::YomiInferrer

      class UnifiedIndexManager
        attr_reader :terms_manager, :glossary_manager, :queue_manager, :markdown_generator

        def initialize
          @terms_manager = IndexTermsManager.new
          @glossary_manager = GlossaryTermsManager.new
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

          # 1. 手動マークアップを検出して index_terms.yml に登録
          manual_terms = extract_manual_markup_terms(chapters)
          if manual_terms.any?
            @terms_manager.merge_terms!(manual_terms, source: 'manual_markup')
            Common.log_info("手動マークアップから #{manual_terms.size} 件の用語を登録しました")
          end

          # auto_discovery が無効の場合、自動候補抽出をスキップ
          unless auto_discovery
            Common.log_info('auto_discovery: false のため、自動候補抽出をスキップします')
            Common.log_info('手動マークアップ [用語|読み] のみが索引に反映されます')
            return
          end

          # 2. 候補抽出
          candidates = extract_candidates(chapters)
          Common.log_info("候補抽出: #{candidates.size}件")

          # 3. 既存の承認済み用語とリジェクト済み用語を除外
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
          @terms_manager.merge_terms!(auto_approved, source: 'auto_extracted') if auto_approved.any?

          # 5. 中スコア候補をHigh/Lowに分割
          review_candidates = filtered_candidates
                              .select { |c| c['score'] >= review_threshold && c['score'] < auto_threshold }
                              .map { |candidate| normalize_candidate(candidate).merge('is_new' => true) }

          high_candidates, low_candidates = split_candidates_by_ratio(review_candidates, high_ratio)

          # 6. 登録済み用語に文脈を付与
          terms_with_context = enrich_terms_with_context(@terms_manager.load_existing_terms, chapters)

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

          # 9. 結果レポート
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

          # 索引承認処理
          if index_approved.any?
            @terms_manager.merge_terms!(index_approved, source: 'auto_extracted')
            index_count = index_approved.size
            changes_made = true
          end

          # 用語集承認処理（説明文付き）
          if glossary_approved.any?
            validate_glossary_definitions!(glossary_approved)
            @glossary_manager.merge_terms!(glossary_approved, source: 'review')
            glossary_count = glossary_approved.size
            changes_made = true
          end

          # 索引のみリジェクト（[-i]）
          if index_rejected.any?
            index_rejected.each { @terms_manager.remove_term!(it['term']) }
            # rejected にも保存（kind: 'index' で区別）
            @queue_manager.save_rejected_terms(index_rejected)
            changes_made = true
          end

          # 用語集のみリジェクト（[-g]）
          if glossary_rejected.any?
            glossary_rejected.each { @glossary_manager.remove_term!(it['term']) }
            # rejected にも保存（kind: 'glossary' で区別）
            @queue_manager.save_rejected_terms(glossary_rejected)
            changes_made = true
          end

          # 両方リジェクト（[r]）
          if both_rejected.any?
            both_rejected.each do |term|
              @terms_manager.remove_term!(term['term']) if @terms_manager.term_names.include?(term['term'])
              @glossary_manager.remove_term!(term['term']) if @glossary_manager.term_names.include?(term['term'])
            end
            @queue_manager.save_rejected_terms(both_rejected)
            changes_made = true
          end

          # リジェクト解除処理
          if unreject.any?
            unreject.each { @queue_manager.unreject_term_by_name!(it['term']) }
            changes_made = true
          end

          # 読み変更処理
          if yomi_changes.any?
            @terms_manager.update_yomi!(yomi_changes)
            changes_made = true
          end

          if changes_made
            Common.log_success("索引: #{index_count}件、用語集: #{glossary_count}件、リジェクト: #{both_rejected.size}件")
            Common.log_info("読み変更: #{yomi_changes.size}件") if yomi_changes.any?
            Common.log_success('index_terms.yml / glossary_terms.yml を更新しました')
            Common.log_info('ページ生成は vs build 実行時に行われます')
          else
            Common.log_warn('変更がありませんでした')
            Common.log_info('_index_glossary_review.md でフラグを編集してください')
          end

          @markdown_generator.cleanup!
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

        # 索引ページを生成（内部用 - vs build から呼ばれる）
        # @param chapters [Array<String>] 対象章のリスト
        def build_index!(chapters)
          Common.log_action('索引ページを生成しています...')

          # 本文スキャン（contents/ のファイルは書き換えない）
          scanner = IndexMatchScanner.new(defer_warnings: true)
          scanner.scan_all_chapters!(chapters, read_only: false)

          # 索引ページ生成
          builder = IndexPageBuilder.new
          builder.build!

          Common.log_success('索引ページを生成しました')

          if scanner.config_missing || scanner.no_matches
            IndexCommands.add_post_build_message(IndexCommands::INDEX_TERMS_MISSING_MESSAGE)
          end
        end

        # 用語集ページを生成（内部用 - vs build から呼ばれる）
        def build_glossary!
          return unless glossary_enabled?

          Common.log_action('用語集ページを生成しています...')

          builder = GlossaryPageBuilder.new
          result = builder.build!

          Common.log_success('用語集ページを生成しました') if result
        end

        # 用語集機能が有効か
        def glossary_enabled?
          @glossary_config[:enabled] == true
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

        # 設定を読み込み（シンボルキー前提）
        # 共通設定（index_glossary）と個別設定（index）をマージ
        # @return [Hash] index設定
        def load_index_config
          shared = load_shared_config
          idx = Common::CONFIG.index
          idx_hash = idx.respond_to?(:to_h) ? idx.to_h : (idx || {})
          shared.merge(idx_hash)
        end

        # glossary設定を読み込み
        # 共通設定（index_glossary）と個別設定（glossary）をマージ
        # @return [Hash] glossary設定
        def load_glossary_config
          shared = load_shared_config
          gls = Common::CONFIG.glossary
          gls_hash = gls.respond_to?(:to_h) ? gls.to_h : (gls || {})
          shared.merge(gls_hash)
        rescue StandardError
          load_shared_config
        end

        # 共通設定（index_glossary）を読み込み
        # @return [Hash] 共通設定
        def load_shared_config
          return {} unless Common::CONFIG.respond_to?(:index_glossary)

          shared = Common::CONFIG.index_glossary
          return {} if shared.nil?

          shared.respond_to?(:to_h) ? shared.to_h : {}
        rescue StandardError
          {}
        end

        # 手動マークアップ用語を抽出
        # @param chapters [Array<String>] 対象章のリスト（ベースネームまたはフルパス）
        # @return [Array<Hash>] 手動マークアップ用語のリスト
        def extract_manual_markup_terms(chapters)
          terms = []
          yomi_inferrer = YomiInferrer.new

          chapters.each do |chapter|
            # ベースネームの場合はフルパスに変換
            chapter_path = resolve_chapter_path(chapter)
            next unless chapter_path && File.exist?(chapter_path)

            content = File.read(chapter_path, encoding: 'utf-8')
            # コードフェンス内を除外（```...```）
            content_without_code = content.gsub(/```[\s\S]*?```/, '')
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

          # 重複を除去
          terms.uniq { |t| t['term'] }
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
          existing_yomi = @terms_manager.load_existing_terms.to_h { |t| [t['term'], t['yomi']] }

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
        # @param terms [Array<Hash>] 用語のリスト
        # @param chapters [Array<String>] 対象章のリスト
        # @return [Array<Hash>] 文脈付き用語のリスト
        def enrich_terms_with_context(terms, chapters)
          # 用語集に登録されている用語を取得（定義付き）
          glossary_terms = @glossary_manager.load_existing_terms
          glossary_by_name = glossary_terms.to_h { |t| [t['term'], t] }

          terms.map do |term|
            enriched = term.dup
            glossary_entry = glossary_by_name[term['term']]

            # 用語集への登録状態を反映
            enriched['in_index'] = true
            enriched['in_glossary'] = !glossary_entry.nil?

            # 用語集に定義がある場合は取得
            if glossary_entry && glossary_entry['definition'].to_s.strip.length.positive?
              enriched['definition'] = glossary_entry['definition']
            end

            # 文脈がない場合は本文から抽出
            unless enriched['contexts']&.any?
              context = find_context_for_term(term['term'], chapters)
              enriched['contexts'] = context ? [context] : []
            end

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
            unless enriched['contexts']&.any?
              context = find_context_for_term(item['term'], chapters)
              enriched['contexts'] = context ? [context] : []
            end

            enriched
          end
        end

        # 用語の文脈を本文から検索
        # @param term [String] 用語
        # @param chapters [Array<String>] 対象章のリスト（ベースネームまたはフルパス）
        # @return [Hash, nil] 文脈情報
        def find_context_for_term(term, chapters)
          chapters.each do |chapter|
            # ベースネームの場合はフルパスに変換
            chapter_path = resolve_chapter_path(chapter)
            next unless chapter_path && File.exist?(chapter_path)

            content = File.read(chapter_path, encoding: 'utf-8')
            next unless content.include?(term)

            chapter_name = File.basename(chapter_path, '.*')
            context = extract_surrounding_context(content, term)
            return { 'chapter' => chapter_name, 'context' => context } if context
          end
          nil
        end

        # 章のパスを解決（ベースネーム → フルパス）
        # @param chapter [String] 章名またはパス
        # @return [String, nil] ファイルパス
        def resolve_chapter_path(chapter)
          return chapter if File.exist?(chapter)

          # contents/ ディレクトリ内を探す
          possible_paths = [
            File.join(Common::CONTENTS_DIR, "#{chapter}.md"),
            File.join('.', "#{chapter}.md"),
            "#{chapter}.md"
          ]

          possible_paths.find { |path| File.exist?(path) }
        end

        # 用語の周辺文脈を抽出
        # @param content [String] 本文
        # @param term [String] 用語
        # @return [String] 文脈
        def extract_surrounding_context(content, term)
          context_width = @config[:context_width] || 40
          total_width = context_width * 2
          index = content.index(term)
          return '' unless index

          # 基本の範囲を計算
          ideal_start = index - context_width
          ideal_end = index + term.length + context_width

          # 前方が足りない場合は後方を延長
          if ideal_start < 0
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
          cleaned = cleaned[start_offset..] if start_offset > 0

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
          return start_offset if start_offset > 0

          # 先頭20文字以内で区切りを探す
          search_range = text[0..19]

          # 優先度順: 句読点 > スペース > 助詞
          boundary_patterns = [
            /[。、！？]/,           # 句読点
            /\s+/,                    # スペース
            /[をはがのにでとへやもをって]/ # 助詞・助動詞
          ]

          boundary_patterns.each do |pattern|
            match = search_range.index(pattern)
            next unless match && match > 0 && match < 18

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
          if first_char.match?(/[ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ]/)
            return find_next_word_boundary(text)
          end

          # 2. カタカナで始まり、後続もカタカナが続く場合（単語の途中の可能性）
          #    例: "ブサイト" は "ウェブサイト" の途中
          if first_char.match?(/[ァ-ヴー]/) && text.length > 1
            # 連続するカタカナの終端を探す
            katakana_end = find_katakana_sequence_end(text)
            if katakana_end > 0
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
            if word_boundary_char?(char)
              return i
            end
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
            unless char.match?(/[ァ-ヴー]/)
              return i
            end
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
          truncated = text[0..max_length + 10]

          boundary_patterns = [
            /[。、！？]/,
            /\s+/,
            /[をはがのにでとへやもをって]/
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

        # 結果をレポート（auto_process!用）
        def report_auto_results(auto_approved, high_candidates, low_candidates, auto_threshold, review_threshold,
                                rejected_count)
          Common.log_success('候補抽出完了')
          Common.log_info("自動承認: #{auto_approved.size}件 (スコア≥#{auto_threshold})")
          Common.log_info("推奨候補: #{high_candidates.size}件")
          Common.log_info("一般候補: #{low_candidates.size}件 (#{review_threshold}≤スコア<#{auto_threshold})")

          if rejected_count.positive?
            Common.log_info("リジェクト設定により #{rejected_count} 件の候補を除外しました")
          end

          Common.log_success('_index_review.md を生成しました')
          Common.log_info('ファイルを編集後、vs index:apply を実行してください')
        end
      end
    end
  end
end
