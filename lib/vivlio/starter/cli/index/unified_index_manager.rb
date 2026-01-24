# frozen_string_literal: true

# ================================================================
# Class: UnifiedIndexManager
# ----------------------------------------------------------------
# 責務:
#   索引生成プロセス全体を統括するマネージャー
#   仕様書 indexing_implementation_spec3.md に準拠
#
# 主要メソッド:
#   - auto_process!: 全自動索引候補抽出 → _index_review.md 生成
#   - apply_markdown_review!: Markdownから承認・リジェクトを適用
#   - build_index!: 索引ページを生成（内部用）
# ================================================================

require_relative '../common'
require_relative 'index_terms_manager'
require_relative 'review_queue_manager'
require_relative 'review_markdown_generator'
require_relative 'index_candidate_extractor'
require_relative 'index_match_scanner'
require_relative 'index_page_builder'
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
        attr_reader :terms_manager, :queue_manager, :markdown_generator

        def initialize
          @terms_manager = IndexTermsManager.new
          @queue_manager = ReviewQueueManager.new
          @markdown_generator = ReviewMarkdownGenerator.new
          @config = load_index_config
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
            Common.log_warn('_index_review.md が見つかりません')
            Common.log_info('先に vs index:auto を実行してください')
            return
          end

          # 1. 承認された候補を取得（High/Lowセクションから）
          approved = @markdown_generator.parse_approved

          # 2. リジェクトされた候補を取得（High/Lowセクションから）
          rejected = @markdown_generator.parse_rejected

          # 3. リジェクト解除された候補を取得（Rejectedセクションから）
          unreject = @markdown_generator.parse_unreject

          # 4. 読み変更を取得（Termsセクションから）
          yomi_changes = @markdown_generator.parse_yomi_changes

          # 処理内容を集計
          changes_made = false

          # 承認処理
          if approved.any?
            @terms_manager.merge_terms!(approved, source: 'auto_extracted')
            changes_made = true
          end

          # リジェクト処理
          if rejected.any?
            @queue_manager.save_rejected_terms(rejected)
            changes_made = true
          end

          # リジェクト解除処理
          if unreject.any?
            unreject.each do |term|
              @queue_manager.unreject_term_by_name!(term['term'])
            end
            changes_made = true
          end

          # 読み変更処理
          if yomi_changes.any?
            @terms_manager.update_yomi!(yomi_changes)
            changes_made = true
          end

          if changes_made
            Common.log_success("承認: #{approved.size}件、リジェクト: #{rejected.size}件、リジェクト解除: #{unreject.size}件")

            if yomi_changes.any?
              Common.log_info("読み変更: #{yomi_changes.size}件")
            end

            Common.log_success('index_terms.yml を更新しました')
            Common.log_info('索引ページの生成は vs build 実行時に行われます')
          else
            Common.log_warn('変更がありませんでした')
            Common.log_info('_index_review.md で [ ] を [x] または [r] に変更してください')
          end

          # 作業ファイルを削除
          @markdown_generator.cleanup!
        end

        # 索引ページを生成（内部用 - vs build から呼ばれる）
        # @param chapters [Array<String>] 対象章のリスト
        def build_index!(chapters)
          Common.log_action('索引ページを生成しています...')

          # 本文スキャン（contents/ のファイルは書き換えない）
          scanner = IndexMatchScanner.new
          scanner.scan_all_chapters!(chapters, read_only: false)

          # 索引ページ生成
          builder = IndexPageBuilder.new
          builder.build!

          Common.log_success('索引ページを生成しました')
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
        # @return [Hash] index設定
        def load_index_config
          idx = Common::CONFIG.index
          idx.respond_to?(:to_h) ? idx.to_h : (idx || {})
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

        # 登録済み用語に文脈を付与
        # @param terms [Array<Hash>] 用語のリスト
        # @param chapters [Array<String>] 対象章のリスト
        # @return [Array<Hash>] 文脈付き用語のリスト
        def enrich_terms_with_context(terms, chapters)
          terms.map do |term|
            next term if term['contexts']&.any?

            # 文脈がない場合は本文から抽出
            context = find_context_for_term(term['term'], chapters)
            term.merge('contexts' => context ? [context] : [])
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
          index = content.index(term)
          return '' unless index

          start_pos = [index - context_width, 0].max
          end_pos = [index + term.length + context_width, content.length].min

          raw_context = content[start_pos...end_pos]
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
