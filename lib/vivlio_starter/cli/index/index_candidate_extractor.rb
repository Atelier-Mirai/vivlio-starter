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
require_relative 'context_snippet'
require_relative '../lint/notation_guard'

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

        # 英字の語 1 つ。大文字で始まる（`Kindle`・`HTML`・`Node.js`・`Re:VIEW`）。
        # 前後に英数字が続く位置からは切り出さない——`viewBox` から `Box` を拾っていた。
        ENGLISH_WORD = /[A-Z][A-Za-z0-9]*(?:[.:][A-Za-z]+)?/

        # 専門用語パターン（カタカナ語、英字語など）
        TECHNICAL_TERM_PATTERNS = [
          /[ァ-ヶー]{3,}/, # カタカナ3文字以上
          # 英字の語。空白を挟んで大文字の語や数が続けば 1 語にまとめる。
          # 1 語ずつ切ると「Kindle Previewer」の `Previewer`、「Apple Silicon」の
          # `Silicon`、「Command Line Tools」の `Line` のような断片が候補になっていた
          /(?<![A-Za-z0-9])#{ENGLISH_WORD}(?: (?:#{ENGLISH_WORD}|\d+(?![A-Za-z0-9])))*(?![A-Za-z0-9])/
        ].freeze

        # 語の頭に来る指示語・副詞。「その語」「やや難解」は語ではなく句の断片
        FRAGMENT_HEAD = /\A(?:その|この|あの|どの|やや|とても|もう|まだ|各)/

        # 語の末尾に残った助詞。「前章の」「画像の」は語の後ろに助詞が付いた断片
        FRAGMENT_TAIL = /[^ぁ-ん][のをがはにへでとやも]\z/

        # 数と単位（`1mm`・`2,894`・`50%`・`1 語`）。値であって語ではない
        MEASUREMENT = /\A[\d.,]+\s*(?:[a-zA-Z%]+|[ぁ-んァ-ヶ一-龯]{1,2})?\z/

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
          extract_heading_terms!

          # TF-IDF スコアリング
          calculate_tfidf_scores!

          # 語の形ではなく置かれ方で分かる非語（表の列の値・定型句）を候補から外す
          discard_structural_terms!

          Common.log_success("#{@scoring.terms.size} 件の候補語を抽出しました")
        end

        # 辞書に登録済みの用語へ、候補と**同じ式**でスコアを与える。
        #
        # 帯の判定（推奨候補・見直し候補）は登録語と未登録候補を同じ土俵で
        # 並べて決めるので、候補として抽出されなかった語——手動登録や
        # ライブラリ取込——にも順位が要る。
        #
        # 候補側と揃わない点が 1 つある: 定義パターンと名詞連続の性質は
        # 本文走査で付くものなので、ここでは判定しない（語の形から分かる
        # :technical と、見出しの照合で分かる :heading だけ付ける）。
        # 見出しの加点を付けないと、候補だけが 45 点を得て、見出しに出る登録語
        # （交ぜ書き・体言止め）が軒並み見直し候補へ押し出されていた。そのぶん控えめなスコアになるため、
        # **手動登録の語は見直し候補へ出さない**（呼び出し側の責務）。
        #
        # @param terms [Array<Hash>] 辞書の用語（'term' と任意の 'pattern' を持つ）
        # @return [Hash{String => Float}] 用語 → スコア（原稿に出現しない語は含まない）
        def score_terms(terms)
          return {} if @documents.empty?

          engine = ScoringEngine.new
          doc_count = @documents.size
          contents = prose_documents

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
            # 1 回も出てこない語は記録しない。observe は tf を見て黙るが mark は
            # 語の綴りだけで通るため、性質ボーナスだけのスコアが残っていた。
            # すると出現ゼロの語が「スコア: 15.0」と表示され、レビューで
            # 「[原稿に出現しません]」に振り分けられない（死語が生きて見える）。
            next if tf.zero?

            engine.mark(name, :technical) if TECHNICAL_TERM_PATTERNS.any? { name.match?(it) }
            engine.mark(name, :heading) if heading_topic?(pattern)
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
            each_noun_sequence(mecab, text) { process_noun_sequence(it, chapter, content) }
          end
        rescue LoadError
          # natto が利用できない場合はスキップ
        end

        # テキストの名詞連続を 1 つずつ渡す。
        # @yieldparam nouns [Array<Array(String, Boolean, String)>] [表層形, 直前に空白があったか, 品詞細分類]
        def each_noun_sequence(mecab, text)
          text.each_line do |line|
            each_noun_sequence_in_line(mecab, line.chomp) { yield without_okurigana_suffix(it) }
          end
        end

        # 語の後ろに付いて句を作る接尾語。IPADIC はこれらを名詞（接尾）とするので、名詞連続に
        # 付いて「日本語ならでは」「Apple Books 向け」が候補になっていた（改善案 #99）。
        # 送り仮名つきの接尾語をまとめて外すと「箇条書き」が「箇条」に削れるので、列挙する
        PHRASE_SUFFIXES = %w[ならでは 向け 付き 済み ごと].freeze

        # 末尾の句を作る接尾語を外す（「Apple Books 向け」→「Apple Books」）
        def without_okurigana_suffix(nouns)
          nouns = nouns.dup
          nouns.pop while nouns.any? && nouns.last[2] == '接尾' && PHRASE_SUFFIXES.include?(nouns.last[0])
          nouns
        end

        # 1 行ぶん。行ごとに解析するのは、名詞連続が行をまたいでつながらないようにするため
        def each_noun_sequence_in_line(mecab, line)
          current_nouns = []
          mecab.parse(line) do |node|
            if node.is_eos?
              yield current_nouns
              current_nouns = []
              next
            end

            pos, pos_detail = node.feature.split(',')
            # 直前に空白があったか（rlength は前の空白を含む長さ）。連結で空白を
            # 落とすと「閲覧用 PDF」が「閲覧用PDF」になり、本文と一致しなくなる
            token = [node.surface, node.rlength > node.length, pos_detail]

            # 空白の後に置かれた記号だけの名詞（IPADIC は `/` を名詞とする）は連続を切る。
            # インラインコードを消した「`error` / `warn` / `info`」の跡が「/ / /」という候補に
            # なっていた。空白を挟まない記号は語の一部（`Re:VIEW`・`Node.js`）なので残す
            if pos == '名詞' && !(token[1] && !node.surface.match?(/[\p{L}\p{N}]/))
              current_nouns << token
            elsif pos == '接頭詞' && pos_detail == '名詞接続'
              # 接頭辞は次の名詞と 1 語をなす（「単章ビルド」「同梱画像」）。
              # 連続の途中で切ると「章ビルド」「梱画像」という断片が候補になる
              yield current_nouns
              current_nouns = [token]
            else
              yield current_nouns
              current_nouns = []
            end
          end
        end

        # 節の見出し（## 〜 ####）
        HEADING = /^\#{2,4}[ \t]+(.+?)[ \t]*$/

        # この数を超える章の見出しに出る語は、構成の言葉（「まとめ」「設定」「使い方」）とみなす。
        # 実測（本書 27 章）で 5 章以上に出るのは トラブルシューティング・設定・画像・まとめ など
        # 構成語ばかりで、要語は数式・Kindle・改ページの 4 章が最多だった
        HEADING_STRUCTURAL_CHAPTERS = 4

        # 見出しに出る語を拾う。見出しは「この節は何を説明するか」の宣言なので、そこに
        # 出る語は索引の入口になりやすく、その節が説明箇所（主要参照）になる。
        #
        # 本文の名詞連続は 3 文字以上・単独名詞は 5 文字以上に絞っている（短い語まで拾うと
        # 「方法」「場合」で埋まる）。そのため扉絵・表紙・脚注・数式のような 2 字の要語は、
        # 何十回出ても候補にならなかった。**見出しに出る語に限って短い語も通す**。
        def extract_heading_terms!
          return unless @yomi_inferrer.available?

          require 'natto'
          mecab = Natto::MeCab.new
          chapters_by_term = Hash.new { |h, k| h[k] = Set[] }

          headings_by_chapter.each do |chapter, headings|
            headings.each do |heading|
              each_noun_sequence(mecab, heading) do |nouns|
                term = join_nouns(nouns)
                chapters_by_term[term] << chapter if heading_term?(term, nouns)
              end
            end
          end

          chapters_by_term.each do |term, chapters|
            next if chapters.size > HEADING_STRUCTURAL_CHAPTERS

            @scoring.mark(term, :heading)
            chapters.each { @term_contexts[term] << { chapter: it, context: extract_context(@documents[it], term) } }
          end
        rescue LoadError
          # natto が利用できない場合はスキップ
        end

        # 語が節の見出しに出るか。構成の言葉（多くの章の見出しに出る語）は数えない
        def heading_topic?(pattern)
          chapters = headings_by_chapter.count { |_, headings| headings.any? { it.match?(pattern) } }
          chapters.between?(1, HEADING_STRUCTURAL_CHAPTERS)
        end

        # 章ごとの見出し（語の切り出しに要らないものを外したもの）
        def headings_by_chapter
          @headings_by_chapter ||= @documents.transform_values do |content|
            CodeBlockStripper.strip(content).scan(HEADING).flatten.map { sanitize_heading(it) }
          end
        end

        # 見出しから、語の切り出しに要らないもの（インラインコード・ラベル・強調）を外す
        def sanitize_heading(heading)
          heading.gsub(/`[^`]*`/, ' ').gsub(/(?<![\w.])@[\w:.-]+/, ' ').delete('*')
        end

        # 単独の名詞として見出しから拾う品詞（MeCab の細分類）。
        # 見出しには「指摘」「検査」「修正」のような動作の名詞（サ変接続）や「無効」「推奨」の
        # ような形容動詞の語幹も多く、これらは節の話題ではなく節の中でする作業を表す
        HEADING_SINGLE_NOUN_KINDS = %w[一般 固有名詞].freeze

        # 見出しから拾ってよい語か。短い語も通すが、ひらがなだけの語（「とき」「もの」）と
        # 1 字の語（「章」「図」）は語として弱いので落とす
        def heading_term?(term, nouns)
          return false if nouns.size == 1 && !HEADING_SINGLE_NOUN_KINDS.include?(nouns.first[2])

          term.length >= 2 && term.match?(/[ァ-ヶ一-龯A-Za-z]/) && valid_term?(term)
        end

        # 名詞連続を 1 語へ。空白があった位置には空白を残す
        def join_nouns(nouns)
          nouns.each_with_index.map { |(surface, spaced), i| i.positive? && spaced ? " #{surface}" : surface }.join
        end

        # 名詞連続を処理。単独名詞も MeCab が 1 語と認識した複合語なら拾う。
        # @param nouns [Array<Array(String, Boolean)>] [表層形, 直前に空白があったか]
        def process_noun_sequence(nouns, chapter, content)
          return if nouns.empty? || nouns.size > 5

          term = join_nouns(nouns)
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
          contents = prose_documents

          # tf（延べ出現数）と df（出現文書数）は同じ走査で数える。
          # 語数 × 文書数の全走査になるので、2 度回さない。
          @scoring.terms.each do |term|
            tf = 0
            df = 0
            pattern = occurrence_pattern(term)
            contents.each do |content|
              n = content.scan(pattern).size
              next if n.zero?

              tf += n
              df += 1
            end
            @scoring.observe(term, tf:, df:, doc_count:)
            term_frequencies[term] = tf
          end
        end

        # 候補ごとの延べ出現数（calculate_tfidf_scores! が数えたもの）
        def term_frequencies = @term_frequencies ||= {}

        # 表のセルの中身がその語だけ、というセルがこの数以上あり、かつ出現のこの割合以上を
        # 占める語は、表の列の値とみなす。割合も見るのは、本文によく出る語（Kindle は 99 回中
        # セルが 3 回）が比較表の行見出しにもなるため
        TABLE_LABEL_MIN_CELLS = 3
        TABLE_LABEL_SHARE = 0.5

        # 定型句の判定。これ以上出現し、直後の数文字が同じ出現がこの割合以上なら定型句
        BOILERPLATE_MIN_OCCURRENCES = 5
        BOILERPLATE_SHARE = 0.6
        BOILERPLATE_TAIL = 6

        # 置かれ方で分かる非語を候補から外す。どちらも語の形からは判別できない。
        #
        # 表の列の値: 早見表の「解説章」列に「拡張リファレンス」が 39 回並ぶと、
        #   その語は本の中の索引語のように数えられる。セルの中身がその語だけという
        #   出現が並ぶのは、列の値（ラベル）の特徴である。
        # 定型句: 「表示結果は次のようになります」の「表示結果」は、21〜23 章で 70 回
        #   同じ文の中に出る。語の使われ方が 1 通りしかないのは、説明ではなく決まり文句。
        def discard_structural_terms!
          labels = table_cell_labels
          @scoring.terms.each do |term|
            @scoring.discard(term) if table_label?(term, labels[term]) || boilerplate?(term) || enclosed?(term)
          end
        end

        # より長い候補の中にしか出てこない語か。「ギリシャ」は本文の 3 回とも「ギリシャ文字」の
        # 一部で、カタカナの並びとして切り出されただけだった（改善案 #99）。長いほうの候補が
        # 同じ回数以上出ていれば、短いほうが単独で使われた箇所はない
        def enclosed?(term)
          tf = term_frequencies[term].to_i
          return false if tf.zero?

          pattern = occurrence_pattern(term)
          longer_terms.any? do |longer, longer_tf|
            longer_tf >= tf && longer.length > term.length && longer.include?(term) && longer.match?(pattern)
          end
        end

        # 長さ 3 字以上の候補と出現数（enclosed? の照合相手）
        def longer_terms = @longer_terms ||= term_frequencies.select { |term, tf| term.length >= 3 && tf.positive? }

        def table_label?(term, cells)
          return false if cells < TABLE_LABEL_MIN_CELLS

          cells >= prose_documents.sum { it.scan(occurrence_pattern(term)).size } * TABLE_LABEL_SHARE
        end

        # 表のセルの中身（強調とインラインコードの記号を外したもの）の出現数
        def table_cell_labels
          counts = Hash.new(0)
          @documents.each_value do |content|
            CodeBlockStripper.strip(content).each_line do |line|
              next unless line.lstrip.start_with?('|')

              line.strip.split('|').drop(1).each { counts[it.gsub(/\*\*|`/, '').strip] += 1 }
            end
          end
          counts
        end

        # 語の直後に続く数文字が、出現の大半で同じか。続きがひらがな（助詞）で始まるものに
        # 限る——「Re:VIEW Starter」「トンボ・塗り足し付き」のような決まった組み合わせの名前は
        # 続きが同じでも定型句ではない。
        def boilerplate?(term)
          pattern = /#{occurrence_pattern(term)}(.{#{BOILERPLATE_TAIL}})/
          tails = prose_documents.flat_map { it.scan(pattern).flatten }
          return false if tails.size < BOILERPLATE_MIN_OCCURRENCES

          tail, count = tails.tally.max_by { _2 }
          tail.match?(/\A[ぁ-ん]/) && count >= tails.size * BOILERPLATE_SHARE
        end

        # 語の出現を数える綴り。英字・カタカナの語は、同じ字種の語の一部として出る位置を数えない
        # （綴りの解釈は TermPattern.bounded）
        def occurrence_pattern(term) = (@occurrence_patterns ||= {})[term] ||= TermPattern.bounded(term)

        # 出現数を数える本文（抽出と同じくコード・機械データ・画像の記法などを除いたもの）。
        # 生の原稿で数えると、抽出で読まなかった箇所の出現まで数えてしまう——図解注釈の
        # 例の画像を 7 回使う「バイオリン」が、本文には 1 回しか出ないのに上位へ来ていた。
        def prose_documents = @prose_documents ||= @documents.values.map { sanitize_content_for_extraction(it) }

        # 語の使われ方の抜粋（語を含む 1 文。切り方は ContextSnippet が唯一の定義元）
        def extract_context(content, term) = ContextSnippet.around(content, term, width: @context_width)

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

          # 図解注釈・実行結果・端末の記録は、紙面に文として出ない機械データなので読まない。
          # 図解注釈の著者コメント（「愛用のバイオリン」）が候補の上位に来ていた
          text = strip_machine_data_blocks(text)

          # HTML コメント（`<!-- no-lint -->` など）。下のタグ除去は複数行にまたがると外せない
          text.gsub!(/<!--.*?-->/m, ' ')

          # HTMLタグを除外（索引用のspanタグなど）
          text.gsub!(/<[^>]+>/, ' ')

          # 画像の記法。代替テキストは図の中身の説明で、索引から案内する本文ではない
          # （「バイオリンを弾くアインシュタイン」から人名や物が候補に挙がっていた）
          text.gsub!(/!\[[^\]]*\]\([^)]*\)/, ' ')

          # 相互参照のラベルと参照（`@prime`・`@pageref:ch-build`）。メールアドレスは除く
          text.gsub!(/(?<![\w.])@[\w:.-]+/, ' ')

          # Vivliostyle拡張記法を除外
          # :::フェンス記法（:::{.class}〜:::）
          text.gsub!(/^:::[^\n]*$/, ' ')

          # 画像の属性指定 {width=20%} など
          text.gsub!(/\{[^}]*\}/, ' ')

          # Markdownリンク記法の URL 部分を除外
          text.gsub!(/\]\([^)]+\)/, '] ')

          # インラインコード
          text.gsub!(/`[^`]+`/, ' ')

          # 連続する空白を 1 つに。**改行は残す**——行をまたいで語がつながらないように
          # （見出し「Technical Terms」と次の行の「HTML」が「Technical Terms HTML」になる）
          text.gsub!(/[ \t]*\n\s*/, "\n")
          text.gsub!(/[ \t]+/, ' ')

          text
        end

        # 機械データのブロック（lint の記法ガードと同じ定義）を空行にする
        def strip_machine_data_blocks(text)
          inside = false
          text.lines.map do |line|
            if inside
              inside = false if Lint::NotationGuard::MACHINE_BLOCK_CLOSE.match?(line)
              "\n"
            elsif Lint::NotationGuard::MACHINE_BLOCK_OPEN.match?(line)
              inside = true
              "\n"
            else
              line
            end
          end.join
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
          return false if term.match?(FRAGMENT_HEAD) || term.match?(FRAGMENT_TAIL) || term.match?(MEASUREMENT)

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
