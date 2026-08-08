# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/index_candidate_extractor.rb
# ================================================================
# 責務:
#   テキストから索引候補語を自動抽出する。
#   - 定義パターン検出（「〜とは」「〜を意味する」など）
#   - 名詞連続の抽出（MeCab）
#   - TF-IDF によるスコアリング（重み・係数の定義元は ScoringEngine）
#
# 抽出結果（term_scores / term_contexts）の見せ方は呼び出し元が決める。
# 現在の唯一の出口は UnifiedIndexManager 経由の _index_glossary_review.md である。
# ================================================================

require_relative '../common'
require_relative 'yomi_inferrer'
require_relative 'code_block_stripper'
require_relative 'scoring_engine'
require_relative 'term_pattern'

module VivlioStarter
  module CLI
    module IndexCommands
      # 索引候補語自動抽出クラス
      class IndexCandidateExtractor
        # 定義文から語を切り出すときに、語の一部として許す文字。
        #
        # 素の `.` で 20 文字を取ると、文の途中から機械的に切り出すことになり
        # 「た章のみです。 は本の**目次（章立て）」のような**文の断片**が候補になる。
        # 実測（本書 27 章）では候補 4,053 件のうち **1,359 件がこの類**で、
        # スコア分布と順位を歪め、candidate_pool を上げても本物が出てこない原因だった。
        #
        # `/` `.` `-` は許す——`PDF/X-1a` `Terminal.app` `10-20行目` のような
        # 正当な語を巻き込まないため。
        TERM_CHAR = %r{[^\s。、！？…「」『』（）()\[\]{}#*|`>~:：;；,，\\]}

        # 定義パターン（「〜とは」「〜について」など）
        DEFINITION_PATTERNS = [
          /(#{TERM_CHAR}{2,20})とは[、,]?[^。]*(?:である|です|を意味|を指|という)/,
          /(#{TERM_CHAR}{2,20})(?:について|に関して)(?:は|の)/,
          /(#{TERM_CHAR}{2,20})(?:を|が)(?:定義|説明|解説)/,
          /「(#{TERM_CHAR}{2,20})」(?:とは|は|について)/,
          /(#{TERM_CHAR}{2,20})(?:の概念|の定義|の意味)/
        ].freeze

        # 語として成立しない文字列。定義文の切り出しや名詞連続に混ざる残骸を落とす。
        # 記法の断片（`###MATTR` `**Linux` `|画像`）、句読点をまたいだ文、
        # 記号で始まる・終わる語が対象。
        JUNK_TERM_PATTERN = /[。、！？\r\n\t#*|`>~\[\]()（）「」『』【】]|:{3}|\A[[:space:]\-.:：]|[[:space:]\-.:：]\z/

        # MeCab が 1 語と認識する複合語（「相対性理論」など）を拾う下限。
        #
        # 名詞連続の経路は 2 語以上を対象にするため、**MeCab の辞書に 1 語として
        # 載っている専門用語が丸ごと漏れていた**（「特殊相対性理論」は
        # 「特殊」＋「相対性理論」の 2 語なので拾えるのに、「相対性理論」単体は漏れる）。
        # 短い単独名詞まで拾うと「本」「方法」「場合」で埋まるため長さで絞る。
        SINGLE_NOUN_MIN_LENGTH = 5

        # 専門用語パターン（カタカナ語、英字語など）
        TECHNICAL_TERM_PATTERNS = [
          /[ァ-ヶー]{3,}/, # カタカナ3文字以上
          /[A-Z][a-zA-Z]{2,}/, # 英語の単語
          /[A-Z]{2,}/ # 略語（HTML, CSS など）
        ].freeze

        attr_reader :documents, :term_contexts, :scoring

        # 全ての候補語を取得
        def all_candidates = @scoring.terms

        # 用語 → スコア。算出そのものは ScoringEngine が持つ（重みの二重管理を作らない）。
        def term_scores = @term_scores ||= @scoring.scores

        def initialize
          @documents = {}
          @scoring = ScoringEngine.new
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

          Common.log_success("#{@scoring.terms.size} 件の候補語を抽出しました")
        end

        # 辞書に登録済みの用語へ、候補と**同じ式**でスコアを与える。
        #
        # 帯の判定（推奨候補・見直し候補）は登録語と未登録候補を同じ土俵で
        # 並べて決めるので、候補として抽出されなかった語——手動マークアップや
        # ライブラリ取込——にも順位が要る。
        #
        # 候補側と揃わない点が 1 つある: 定義パターンと名詞連続の性質は
        # 本文走査で付くものなので、ここでは判定しない（語の形から分かる
        # :technical だけ付ける）。そのぶん控えめなスコアになるため、
        # **手動マークアップ由来の語は見直し候補へ出さない**（呼び出し側の責務）。
        #
        # @param terms [Array<Hash>] 辞書の用語（'term' と任意の 'pattern' を持つ）
        # @return [Hash{String => Float}] 用語 → スコア（原稿に出現しない語は含まない）
        def score_terms(terms)
          return {} if @documents.empty?

          engine = ScoringEngine.new
          doc_count = @documents.size
          contents = @documents.values

          terms.each do |entry|
            name = entry['term'].to_s
            next if name.empty?

            tf = 0
            df = 0
            pattern = term_regexp(entry)
            contents.each do |content|
              n = content.scan(pattern).size
              next if n.zero?

              tf += n
              df += 1
            end
            engine.mark(name, :technical) if TECHNICAL_TERM_PATTERNS.any? { name.match?(it) }
            engine.observe(name, tf:, df:, doc_count:)
          end

          engine.scores
        end

        private

        # 辞書エントリの照合パターン（綴りの解釈は TermPattern が唯一の定義元）
        def term_regexp(entry) = TermPattern.for(entry)

        # 定義パターンから候補を抽出
        def extract_definition_patterns!
          @documents.each do |chapter, content|
            # サニタイズしたコンテンツで検索
            sanitized = sanitize_content_for_extraction(content)
            DEFINITION_PATTERNS.each do |pattern|
              sanitized.scan(pattern) do |match|
                term = match[0]&.strip
                next unless valid_term?(term)

                # 性質を記録するだけ（語ごと 1 回）。出現ごとに加算すると
                # TF を二重に数えることになり、頻出語ほど高スコアになる。
                @scoring.mark(term, :definition)

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

                # 語ごと 1 回。カタカナ 3 文字以上はこのパターンに当たるので、
                # 出現ごとに加算すると「ファイル」だけで 371 回 × 15 点になっていた。
                @scoring.mark(term, :technical)

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
                process_noun_sequence(current_nouns, chapter, content)
                current_nouns = []
                next
              end

              features = node.feature.split(',')
              pos = features[0] # 品詞

              if pos == '名詞'
                current_nouns << node.surface
              else
                process_noun_sequence(current_nouns, chapter, content)
                current_nouns = []
              end
            end
          end
        rescue LoadError
          # natto が利用できない場合はスキップ
        end

        # 名詞連続を処理。単独名詞も MeCab が 1 語と認識した複合語なら拾う。
        def process_noun_sequence(nouns, chapter, content)
          return if nouns.empty? || nouns.size > 5

          term = nouns.join
          return if nouns.size == 1 && !compound_noun?(term)
          return if term.length < 3 || term.length > 20
          return unless valid_term?(term)

          # 語ごと 1 回（出現ごとではない）
          @scoring.mark(term, :noun_sequence)

          # コンテキストを記録
          context = extract_context(content, term)
          @term_contexts[term] << { chapter: chapter, context: context }
        end

        # TF-IDF スコアを計算する。式は ScoringEngine が持つ（重みの定義元は 1 箇所）。
        #
        # 旧実装は文書ごとに `tf * idf * 5` を合算しており、結果は
        # `5 * idf * Σtf`——TF に線形だった。性質ボーナス 3 種も出現ごとの加算
        # だったため、スコアは実質「出現数の写し」になっていた。
        def calculate_tfidf_scores!
          return if @documents.empty?

          doc_count = @documents.size
          contents = @documents.values

          # tf（延べ出現数）と df（出現文書数）は同じ走査で数える。
          # 語数 × 文書数の全走査になるので、2 度回さない。
          @scoring.terms.each do |term|
            tf = 0
            df = 0
            contents.each do |content|
              n = content.scan(term).size
              next if n.zero?

              tf += n
              df += 1
            end
            @scoring.observe(term, tf:, df:, doc_count:)
          end
        end

        # 用語の周辺コンテキストを抽出
        # 前方が不足する場合は後方を延長、後方が不足する場合は前方を延長
        def extract_context(content, term)
          idx = content.index(term)
          return '' if idx.nil?

          w = @context_width

          ideal_start = idx - w
          ideal_end = idx + term.length + w

          # 前方不足分を後方に補償
          if ideal_start.negative?
            ideal_end += ideal_start.abs
            ideal_start = 0
          end

          # 後方不足分を前方に補償
          if ideal_end > content.length
            overshoot = ideal_end - content.length
            ideal_start = [ideal_start - overshoot, 0].max
            ideal_end = content.length
          end

          context = content[ideal_start...ideal_end]
          context.gsub(/\s+/, ' ').strip
        end

        # config から context_width を読み込み（既定値 40）
        def load_context_width
          Common::CONFIG.index_glossary.context_width
        end

        # 抽出用にコンテンツをサニタイズ
        # HTMLタグ、Vivliostyle拡張記法、コードブロックなどを除外
        def sanitize_content_for_extraction(content)
          # コード（フェンス／インライン）を除外。素朴な /```...```/ は地の文中の
          # インライン ``` でフェンス対がズレ、コード例をスコア対象にしてしまうため
          # 行頭フェンスを数える状態機械方式で確実に取り除く。
          text = CodeBlockStripper.strip(content)

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

        # MeCab が 1 語と認識した複合語か（「相対性理論」「アイデンティティ」）。
        #
        # 日本語を含む長い語だけを通す。英字のみの単独名詞は `section` `table`
        # `column` のように CSS クラス名や記法由来のものが大半で、実測 153 件中
        # 136 件がそれだった。「・」でつないだ並び（「ヘッダー・フッター・ノンブル」）も
        # 語ではなく列挙なので落とす。
        def compound_noun?(term)
          term.length >= SINGLE_NOUN_MIN_LENGTH &&
            term.match?(/[ぁ-んァ-ヶ一-龯]/) &&
            !term.include?('・')
        end

        # 抽出された用語が有効かどうかを判定
        # @param term [String] 用語
        # @return [Boolean] 有効ならtrue
        def valid_term?(term)
          return false if term.nil? || term.empty?
          return false if term.length < 2

          # 記法・文の断片を落とす（TERM_CHAR で切り出しても名詞連続からは混ざる）
          return false if term.match?(JUNK_TERM_PATTERN)

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
          return false if term.match?(%r{^[="\-./:;,]+$})

          # data属性の値（yomi値）を除外
          return false if term.match?(/^(yomi|index-term|idx-)/)

          true
        end
      end
    end
  end
end
