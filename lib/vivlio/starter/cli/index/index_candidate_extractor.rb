# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/index/index_candidate_extractor.rb
# ================================================================
# 責務:
#   テキストから索引候補語を自動抽出する。
#   - 定義パターン検出（「〜とは」「〜を意味する」など）
#   - 名詞連続の抽出（MeCab）
#   - TF-IDF によるスコアリング
#
# Phase 2 機能:
#   - 自動抽出とスコアリング
#   - 候補 YAML ファイル生成
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'
require_relative 'yomi_inferrer'

module Vivlio
  module Starter
    module CLI
      module IndexCommands
        # 索引候補語自動抽出クラス
        class IndexCandidateExtractor
          BANNER = <<~BANNER.freeze
            # ================================================================
            # 索引候補リスト（config/index_candidates.yml）
            # ================================================================
            # vs index:candidate（内部コマンド）によって自動生成される索引用語候補です。
            #
            # 使い方:
            #   1. contexts で示される章・抜粋を参照し、索引に載せたい語を確認する
            #   2. enabled を true/false に切り替えて採用可否を管理する
            #   3. 採用する語は原稿に [用語|読み] でマークアップ、または index_terms.yml へ登録する
            #   4. 読みが誤っている場合は index_terms.yml に正しい yomi を追加してから再生成する
            # ================================================================
          BANNER

          # 定義パターン（「〜とは」「〜について」など）
          DEFINITION_PATTERNS = [
            /(.{2,20})とは[、,]?[^。]*(?:である|です|を意味|を指|という)/,
            /(.{2,20})(?:について|に関して)(?:は|の)/,
            /(.{2,20})(?:を|が)(?:定義|説明|解説)/,
            /「(.{2,20})」(?:とは|は|について)/,
            /(.{2,20})(?:の概念|の定義|の意味)/
          ].freeze

          # 専門用語パターン（カタカナ語、英字語など）
          TECHNICAL_TERM_PATTERNS = [
            /[ァ-ヶー]{3,}/, # カタカナ3文字以上
            /[A-Z][a-zA-Z]{2,}/, # 英語の単語
            /[A-Z]{2,}/ # 略語（HTML, CSS など）
          ].freeze

          attr_reader :documents, :term_scores, :term_contexts

          # 全ての候補語を取得
          def all_candidates
            @term_scores.keys
          end

          def initialize
            @documents = {}
            @term_scores = Hash.new(0.0)
            @term_contexts = Hash.new { |h, k| h[k] = [] }
            @yomi_inferrer = YomiInferrer.new
            @context_width = load_context_width
          end

          # 全章を解析して索引候補を抽出
          # @param chapters [Array<String>] 対象章のファイル名リスト
          def extract_from_chapters!(chapters)
            Common.log_action('索引候補の自動抽出を開始します...')

            # ドキュメントを読み込み (contents/ 配下のみ)
            chapters.each do |chapter|
              md_file = File.join(Common::CONTENTS_DIR, "#{chapter}.md")

              unless File.exist?(md_file)
                Common.log_warn("索引候補抽出: contents/ に #{chapter}.md が見つからないためスキップします")
                next
              end

              content = File.read(md_file, encoding: 'utf-8')
              @documents[chapter] = content
            end

            # 各種抽出を実行
            extract_definition_patterns!
            extract_technical_terms!
            extract_noun_sequences! if @yomi_inferrer.available?

            # TF-IDF スコアリング
            calculate_tfidf_scores!

            Common.log_success("#{@term_scores.size} 件の候補語を抽出しました")
          end

          # 索引候補を YAML ファイルに出力
          # @param output_file [String] 出力ファイルパス
          # @param threshold [Integer] スコア閾値（この値以上の候補のみ出力）
          def export_candidates!(output_file = 'config/index_candidates.yml', threshold = 150)
            FileUtils.mkdir_p(File.dirname(output_file))

            candidates = @term_scores
                         .select { |_, score| score >= threshold }
                         .sort_by { |_, score| -score }
                         .map do |term, score|
              yomi = @yomi_inferrer.available? ? @yomi_inferrer.infer(term) : term
              contexts = @term_contexts[term]
                           .uniq { |ctx| [ctx[:chapter], ctx[:context]] }
                           .first(3)

              {
                'term' => term,
                'yomi' => yomi,
                'score' => score.round(1),
                'contexts' => contexts,
                'enabled' => true
              }
            end

            data = {
              'generated_at' => Time.now.iso8601,
              'threshold' => threshold,
              'total_candidates' => candidates.size,
              'candidates' => candidates
            }

            yaml = data.to_yaml(line_width: -1)
            yaml_with_spacing = yaml
                                   .sub("candidates:\n- term:", "candidates:\n\n- term:")
                                   .gsub("\n- term:", "\n\n- term:")

            File.write(output_file, "#{BANNER}#{yaml_with_spacing}", encoding: 'utf-8')
            Common.log_success("索引候補を #{output_file} に出力しました")
          rescue StandardError => e
            Common.log_error("索引候補の出力に失敗しました: #{e.message}")
          end

          private

          # 定義パターンから候補を抽出
          def extract_definition_patterns!
            @documents.each do |chapter, content|
              # サニタイズしたコンテンツで検索
              sanitized = sanitize_content_for_extraction(content)
              DEFINITION_PATTERNS.each do |pattern|
                sanitized.scan(pattern) do |match|
                  term = match[0]&.strip
                  next unless valid_term?(term)

                  # スコア加算（定義パターンは高スコア）
                  @term_scores[term] += 30

                  # コンテキストを記録
                  context = extract_context(content, term)
                  @term_contexts[term] << { chapter: chapter, context: context }
                end
              end
            end
          end

          # 専門用語パターンから候補を抽出
          def extract_technical_terms!
            @documents.each do |chapter, content|
              # サニタイズしたコンテンツで検索
              sanitized = sanitize_content_for_extraction(content)
              TECHNICAL_TERM_PATTERNS.each do |pattern|
                sanitized.scan(pattern) do |match|
                  term = match.is_a?(Array) ? match[0] : match
                  next unless valid_term?(term)
                  next if term.length < 3

                  # スコア加算（専門用語は中程度のスコア）
                  @term_scores[term] += 15

                  # コンテキストを記録
                  context = extract_context(content, term)
                  @term_contexts[term] << { chapter: chapter, context: context }
                end
              end
            end
          end

          # MeCab で名詞連続を抽出
          def extract_noun_sequences!
            return unless @yomi_inferrer.available?

            require 'natto'
            mecab = Natto::MeCab.new

            @documents.each do |chapter, content|
              # 不要な要素を除外してからMeCab解析
              text = sanitize_content_for_extraction(content)

              current_nouns = []
              mecab.parse(text) do |node|
                if node.is_eos?
                  process_noun_sequence(current_nouns, chapter, content) if current_nouns.size >= 2
                  current_nouns = []
                  next
                end

                features = node.feature.split(',')
                pos = features[0] # 品詞

                if pos == '名詞'
                  current_nouns << node.surface
                else
                  process_noun_sequence(current_nouns, chapter, content) if current_nouns.size >= 2
                  current_nouns = []
                end
              end
            end
          rescue LoadError
            # natto が利用できない場合はスキップ
          end

          # 名詞連続を処理
          def process_noun_sequence(nouns, chapter, content)
            return if nouns.size < 2 || nouns.size > 5

            term = nouns.join
            return if term.length < 3 || term.length > 20
            return unless valid_term?(term)

            # スコア加算（名詞連続は低～中程度のスコア）
            @term_scores[term] += 10

            # コンテキストを記録
            context = extract_context(content, term)
            @term_contexts[term] << { chapter: chapter, context: context }
          end

          # TF-IDF スコアを計算
          def calculate_tfidf_scores!
            return if @documents.empty?

            doc_count = @documents.size

            # ドキュメント頻度（DF）を計算
            df = Hash.new(0)
            @term_scores.each_key do |term|
              @documents.each_value do |content|
                df[term] += 1 if content.include?(term)
              end
            end

            # TF-IDF を計算してスコアに加算
            @term_scores.each_key do |term|
              idf = Math.log((doc_count + 1.0) / (df[term] + 1.0)) + 1.0

              @documents.each_value do |content|
                tf = content.scan(term).size
                next if tf.zero?

                tfidf = tf * idf * 5 # スケーリング係数
                @term_scores[term] += tfidf
              end
            end
          end

          # 用語の周辺コンテキストを抽出
          def extract_context(content, term)
            idx = content.index(term)
            return '' if idx.nil?

            w = @context_width
            start_idx = [idx - w, 0].max
            end_idx = [idx + term.length + w, content.length].min

            context = content[start_idx...end_idx]
            context.gsub(/\s+/, ' ').strip
          end

          # config から context_width を読み込み（既定値 40）
          def load_context_width
            shared = Common::CONFIG.respond_to?(:index_glossary) ? Common::CONFIG.index_glossary : nil
            shared_hash = shared.respond_to?(:to_h) ? shared.to_h : {}
            shared_hash[:context_width] || 40
          rescue StandardError
            40
          end

          # 抽出用にコンテンツをサニタイズ
          # HTMLタグ、Vivliostyle拡張記法、コードブロックなどを除外
          def sanitize_content_for_extraction(content)
            text = content.dup

            # コードブロックを除外
            text.gsub!(/```[\s\S]*?```/, ' ')

            # HTMLタグを除外（索引用のspanタグなど）
            text.gsub!(/<[^>]+>/, ' ')

            # Vivliostyle拡張記法を除外
            # :::フェンス記法（:::{.class}〜:::）
            text.gsub!(/^:::[^\n]*$/, ' ')

            # 画像の属性指定 {width=20%} など
            text.gsub!(/\{[^}]*\}/, ' ')

            # Markdownリンク記法の URL 部分を除外
            text.gsub!(/\]\([^)]+\)/, '] ')

            # インラインコード
            text.gsub!(/`[^`]+`/, ' ')

            # 連続する空白を1つに
            text.gsub!(/\s+/, ' ')

            text
          end

          # 抽出された用語が有効かどうかを判定
          # @param term [String] 用語
          # @return [Boolean] 有効ならtrue
          def valid_term?(term)
            return false if term.nil? || term.empty?
            return false if term.length < 2

            # HTMLタグの断片を除外
            return false if term.include?('<') || term.include?('>')
            return false if term.include?('</') || term.include?('/>')
            return false if term.match?(/^(span|div|class|id|data-|href|src)$/i)

            # Vivliostyle/Markdown記法の断片を除外
            return false if term.start_with?(':::')
            return false if term.start_with?('{') || term.end_with?('}')
            return false if term.match?(/^(width|height)=/)
            return false if term.match?(/^(align)=/)
            return false if term.match?(/^\d+%$/) # 20%, 25% など

            # 特殊文字のみの用語を除外
            return false if term.match?(/^[="\-\.\/:;,]+$/)

            # data属性の値（yomi値）を除外
            return false if term.match?(/^(yomi|index-term|idx-)/)

            true
          end
        end
      end
    end
  end
end
