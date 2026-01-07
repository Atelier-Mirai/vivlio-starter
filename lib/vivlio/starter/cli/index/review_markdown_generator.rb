# frozen_string_literal: true

# ================================================================
# Class: ReviewMarkdownGenerator
# ----------------------------------------------------------------
# 責務:
#   _index_review.md の生成・解析を担当
#   仕様書 indexing_implementation_spec3.md に準拠
#
# 主要メソッド:
#   - generate!: レビュー用Markdownを生成（4セクション構成）
#   - parse_approved: 承認済み候補を抽出
#   - parse_rejected: リジェクト候補を抽出
#   - parse_unreject: Rejectedセクションで[r]マークされた候補を抽出
# ================================================================

require 'fileutils'
require 'time'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      class ReviewMarkdownGenerator
        REVIEW_FILE = '_index_review.md'

        def initialize
          @content = nil
          @config = load_index_config
        end

        # レビュー用Markdownを生成
        # @param data [Hash] セクション別データ
        #   - :terms [Array<Hash>] 登録済み用語
        #   - :high_candidates [Array<Hash>] 推奨候補
        #   - :low_candidates [Array<Hash>] 一般候補
        #   - :rejected [Array<Hash>] 除外済みリスト
        def generate!(data)
          content = build_markdown(data)
          File.write(REVIEW_FILE, content, encoding: 'utf-8')
          Common.log_success("レビュー用ファイルを生成しました: #{REVIEW_FILE}")
          Common.log_info('ファイルを開いて [ ] を [x] または [r] に変更してください')
          Common.log_info('完了したら: vs index:apply')
        end

        # レビューファイルが存在するか
        # @return [Boolean]
        def exists?
          File.exist?(REVIEW_FILE)
        end

        # 承認済み候補を抽出（High/Lowセクションから[x]マークされたもの）
        # @return [Array<Hash>] 承認済み候補のリスト
        def parse_approved
          return [] unless File.exist?(REVIEW_FILE)

          content = File.read(REVIEW_FILE, encoding: 'utf-8')
          approved = []

          # High Candidates と Low Candidates セクションから [x] を抽出
          # 形式: - [x] `NEW!` **用語** (読み) - スコア: 123.5
          # または: - [x] `Today` **用語** (読み)
          # または: - [x] **用語** (読み) - スコア: 123.5
          content.scan(/^- \[x\](?: `(?:NEW!|Today)`)? \*\*(.+?)\*\* \(([^)]+)\)/) do |term, yomi|
            approved << { 'term' => term, 'yomi' => yomi }
          end

          approved
        end

        # リジェクト候補を抽出（High/Lowセクションから[r]マークされたもの）
        # @return [Array<Hash>] リジェクト候補のリスト
        def parse_rejected
          return [] unless File.exist?(REVIEW_FILE)

          content = File.read(REVIEW_FILE, encoding: 'utf-8')
          rejected = []

          # Rejectedセクション以外から [r] マークを抽出
          # Rejectedセクションの開始位置を特定
          rejected_section_start = content.index('## 4. 除外済みリスト')

          search_content = if rejected_section_start
                             content[0...rejected_section_start]
                           else
                             content
                           end

          search_content.scan(/^- \[r\](?: `(?:NEW!|Today)`)? \*\*(.+?)\*\* \(([^)]+)\)(?: - スコア: ([\d.]+))?/) do |term, yomi, score|
            entry = { 'term' => term, 'yomi' => yomi }
            entry['score'] = score.to_f if score
            rejected << entry
          end

          rejected
        end

        # Rejectedセクションで[r]マークされた候補を抽出（リジェクト解除用）
        # @return [Array<Hash>] リジェクト解除候補のリスト
        def parse_unreject
          return [] unless File.exist?(REVIEW_FILE)

          content = File.read(REVIEW_FILE, encoding: 'utf-8')
          unreject = []

          # Rejectedセクションを特定
          rejected_section_start = content.index('## 4. 除外済みリスト')
          return [] unless rejected_section_start

          rejected_content = content[rejected_section_start..]

          # Rejectedセクション内で [r] マークされたものを抽出
          rejected_content.scan(/^- \[r\](?: `(?:NEW!|Today)`)? \*\*(.+?)\*\* \(([^)]+)\)(?: - スコア: ([\d.]+))?/) do |term, yomi, score|
            unreject << { 'term' => term, 'yomi' => yomi }
          end

          unreject
        end

        # Termsセクションで読みが変更された用語を抽出
        # @return [Array<Hash>] 読み変更された用語のリスト
        def parse_yomi_changes
          return [] unless File.exist?(REVIEW_FILE)

          content = File.read(REVIEW_FILE, encoding: 'utf-8')
          changes = []

          # Termsセクションを特定
          terms_section_start = content.index('## 1. 登録済み用語の確認')
          high_section_start = content.index('## 2. 推奨候補')

          return [] unless terms_section_start

          terms_end = high_section_start || content.length
          terms_content = content[terms_section_start...terms_end]

          # [x] マークされた用語の読みを抽出
          terms_content.scan(/^- \[x\](?: `(?:NEW!|Today)`)? \*\*(.+?)\*\* \(([^)]+)\)/) do |term, yomi|
            changes << { 'term' => term, 'yomi' => yomi }
          end

          changes
        end

        # レビューファイルを削除
        def cleanup!
          FileUtils.rm_f(REVIEW_FILE)
        end

        private

        # 設定を読み込み
        def load_index_config
          config = Common::CONFIG || {}
          config['index'] || {}
        end

        # Markdown形式を構築
        # @param data [Hash] セクション別データ
        # @return [String] Markdown文字列
        def build_markdown(data)
          terms = data[:terms] || []
          high_candidates = data[:high_candidates] || []
          low_candidates = data[:low_candidates] || []
          rejected = data[:rejected] || []

          <<~MARKDOWN
            # 索引レビュー
            ※ [x]で承認、[r]で棄却。読みの修正は ( ) 内を編集してください。

            #{build_terms_section(terms)}

            #{build_high_candidates_section(high_candidates)}

            #{build_low_candidates_section(low_candidates)}

            #{build_rejected_section(rejected)}
          MARKDOWN
        end

        # 1. 登録済み用語セクション
        def build_terms_section(terms)
          # 無効な用語をフィルタリング（手動マークアップは除外しない）
          valid_terms = terms.reject { |t| should_filter_term?(t) }
          section = "## 1. 登録済み用語の確認 (Terms: #{valid_terms.size}語)\n\n"

          if valid_terms.empty?
            section += "登録済みの用語はありません。\n"
          else
            sorted_terms = sort_by_label_and_appearance(valid_terms)
            sorted_terms.each do |t|
              section += build_term_line(t, checked: true)
            end
          end

          section
        end

        # 用語をフィルタリングすべきかどうかを判定
        # 手動マークアップ用語は著者の意図があるためフィルタリングしない
        # @param term [Hash] 用語データ
        # @return [Boolean] フィルタリングすべきならtrue
        def should_filter_term?(term)
          # 手動マークアップは著者の意図があるのでフィルタリングしない
          return false if term['source'] == 'manual_markup'

          # 自動抽出された用語のみフィルタリング
          invalid_index_term?(term['term'])
        end

        # 索引として不適切な用語かどうかを判定（自動抽出用語向け）
        # @param term_text [String] 用語テキスト
        # @return [Boolean] 不適切ならtrue
        def invalid_index_term?(term_text)
          return true if term_text.nil? || term_text.empty?

          # 脚注参照 (^1, ^firefox-devtool など)
          return true if term_text.start_with?('^')

          # カラーコード (#e74c3c, '#e74c3c' など)
          return true if term_text.match?(/^['"]?#[0-9a-fA-F]{3,8}['"]?/)

          # 数字のみ
          return true if term_text.match?(/^\d+$/)

          # 演算子・記号のみ (&&, ||, !, &, | など)
          return true if term_text.match?(/^[&|!<>=+\-*\/%^~]+$/)

          # HTMLタグ風 (<h1>, </h1>, <!DOCTYPE> など)
          return true if term_text.match?(/^<\/?[a-zA-Z!]/)

          false
        end

        # 2. 推奨候補セクション
        def build_high_candidates_section(candidates)
          section = "## 2. 推奨候補 (High Candidates: #{candidates.size}語)\n\n"

          if candidates.empty?
            section += "推奨候補はありません。\n"
          else
            sorted = sort_by_label_and_appearance(candidates)
            sorted.each do |c|
              section += build_candidate_line(c)
            end
          end

          section
        end

        # 3. 一般候補セクション
        def build_low_candidates_section(candidates)
          section = "## 3. 一般候補 (Low Candidates: #{candidates.size}語)\n\n"

          if candidates.empty?
            section += "一般候補はありません。\n"
          else
            sorted = sort_by_label_and_appearance(candidates)
            sorted.each do |c|
              section += build_candidate_line(c)
            end
          end

          section
        end

        # 4. 除外済みリストセクション（Candidatesと同様の形式、rejected_atでラベル判定）
        def build_rejected_section(rejected)
          section = "## 4. 除外済みリスト (Rejected: #{rejected.size}語)\n"
          section += "※ 間違えて除外したものは [r] を入れると、候補(Candidates)に復帰します。\n\n"

          if rejected.empty?
            section += "除外済みの用語はありません。\n"
          else
            # ラベルと出現順でソート
            sorted = sort_rejected_by_label(rejected)
            sorted.each { |item| section += build_rejected_line(item) + "\n" }
          end

          section
        end

        # 用語行を構築（Termsセクション用）- Candidatesと同様の形式
        def build_term_line(term, checked: false)
          term_text = term['term']
          yomi = term['yomi'] || term_text
          label = determine_label(term)
          score = term['score']
          source = term['source']
          checkbox = checked ? '[x]' : '[ ]'

          line = "- #{checkbox}"
          line += " `#{label}`" if label
          line += " **#{term_text}** (#{yomi})"
          # 手動マークアップは「[手動登録]」、それ以外はスコア表示
          if source == 'manual_markup'
            line += ' - [手動登録]'
          elsif score
            line += " - スコア: #{score.round(1)}"
          end
          line += "\n"

          # 文脈を最大2件表示（Candidatesと同様）
          contexts = term['contexts'] || []
          contexts.first(2).each do |ctx|
            chapter = ctx['chapter'] || '不明'
            context_text = extract_context(ctx['context'])
            line += "  - #{chapter} - \"#{context_text}\"\n"
          end

          line + "\n"
        end

        # 除外済み行を構築
        def build_rejected_line(item, checkbox: '[ ]')
          term = item['term']
          yomi = item['yomi'] || term
          score = normalize_score(item['score'])
          label = determine_rejected_label(item)
          contexts = item['contexts'] || []

          line = "- #{checkbox}"
          line += " `#{label}`" if label
          line += " **#{term}** (#{yomi})"
          line += " - スコア: #{score.round(1)}" if score
          line += "\n"

          contexts.first(2).each do |ctx|
            chapter = ctx['chapter'] || '不明'
            context_text = extract_context(ctx['context'])
            line += "  - #{chapter} - \"#{context_text}\"\n"
          end

          line
        end

        def normalize_score(raw_score)
          return nil if raw_score.nil?
          return raw_score.to_f if raw_score.is_a?(Numeric)

          Float(raw_score)
        rescue ArgumentError, TypeError
          nil
        end

        # 候補行を構築（High/Lowセクション用）
        def build_candidate_line(candidate)
          term = candidate['term']
          yomi = candidate['yomi'] || term
          score = candidate['score'] || 0
          label = determine_label(candidate)
          contexts = candidate['contexts'] || []

          line = '- [ ]'
          line += " `#{label}`" if label
          line += " **#{term}** (#{yomi}) - スコア: #{score.round(1)}\n"

          # 文脈を最大2件表示
          contexts.first(2).each do |ctx|
            chapter = ctx['chapter'] || '不明'
            context_text = extract_context(ctx['context'])
            line += "  - #{chapter} - \"#{context_text}\"\n"
          end

          line + "\n"
        end

        # ラベルを決定（NEW! または Today）
        def determine_label(item)
          approved_at = item['approved_at']
          is_new = item['is_new']

          return 'NEW!' if is_new

          return nil unless approved_at

          # タイムゾーンを取得
          timezone = @config['timezone'] || 'Asia/Tokyo'
          begin
            tz = TZInfo::Timezone.get(timezone)
            now = tz.now
            today_start = Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)

            approved_time = if approved_at.is_a?(String)
                              Time.parse(approved_at)
                            else
                              approved_at
                            end

            return 'Today' if approved_time >= today_start
          rescue StandardError
            # TZInfo が使えない場合はローカルタイムで判定
            today_start = Time.now.to_date.to_time
            approved_time = approved_at.is_a?(String) ? Time.parse(approved_at) : approved_at
            return 'Today' if approved_time >= today_start
          end

          nil
        end

        # ラベルと出現順でソート
        def sort_by_label_and_appearance(items)
          items.sort_by do |item|
            label = determine_label(item)
            priority = case label
                       when 'NEW!' then 0
                       when 'Today' then 1
                       else 2
                       end
            first_chapter = (item['contexts']&.first || {})['chapter'] || 'zzz'
            [priority, first_chapter, item['term']]
          end
        end

        # Rejectedセクション用のソート（rejected_atでラベル判定）
        def sort_rejected_by_label(items)
          items.sort_by do |item|
            label = determine_rejected_label(item)
            priority = case label
                       when 'NEW!' then 0
                       when 'Today' then 1
                       else 2
                       end
            first_chapter = (item['contexts']&.first || {})['chapter'] || 'zzz'
            [priority, first_chapter, item['term']]
          end
        end

        # Rejectedセクション用のラベル決定（rejected_atを使用）
        def determine_rejected_label(item)
          rejected_at = item['rejected_at']
          is_new = item['is_new']

          return 'NEW!' if is_new

          return nil unless rejected_at

          # タイムゾーンを取得
          timezone = @config['timezone'] || 'Asia/Tokyo'
          begin
            tz = TZInfo::Timezone.get(timezone)
            now = tz.now
            today_start = Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)

            rejected_time = if rejected_at.is_a?(String)
                              Time.parse(rejected_at)
                            else
                              rejected_at
                            end

            return 'Today' if rejected_time >= today_start
          rescue StandardError
            # TZInfo が使えない場合はローカルタイムで判定
            today_start = Time.now.to_date.to_time
            rejected_time = rejected_at.is_a?(String) ? Time.parse(rejected_at) : rejected_at
            return 'Today' if rejected_time >= today_start
          end

          nil
        end

        # 文脈を抽出（設定に基づいて）
        def extract_context(context_text)
          return '' if context_text.nil? || context_text.empty?

          # 改行を除去
          text = context_text.to_s.gsub(/[\r\n]+/, ' ').strip

          context_width = @config['context_width'] || 40

          if text.length <= context_width * 2
            text
          else
            # smart_context_cutting は抽出時に適用されているため、ここでは単純にトリム
            text[0..(context_width * 2)]
          end
        end
      end
    end
  end
end
