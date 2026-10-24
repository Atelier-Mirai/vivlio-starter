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
require_relative '../math_delimiters'
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
        TERM_CHAR = %r{[^\s。、！？…「」『』（）()\[\]{}#*|`>~:：;；,，\\〓]}

        # 本文から外した数式の跡（strip_math）。MeCab は記号として読み、名詞の連続を切る。
        # 語の文字（TERM_CHAR）にも、語の残骸の判定（JUNK_TERM_PATTERN）にも含めない
        MATH_GAP = '〓'

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
        JUNK_TERM_PATTERN = /[。、！？\r\n\t#*|`>~\[\]()（）「」『』【】〓]|:{3}|\A[[:space:]\-.:：]|[[:space:]\-.:：]\z/

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

        # 語の頭に来る指示語・副詞。「その語」「やや難解」は語ではなく句の断片。
        # 助詞で始まり、すぐ仮名以外が続くもの（「の級数」「の絶対値」）も、前の語が
        # 数式やコードとして外された跡の断片。「のれん」のように仮名が続く語は残す
        FRAGMENT_HEAD = /\A(?:その|この|あの|どの|やや|とても|もう|まだ|各|[のをがはにへでとやも](?=[^ぁ-ん]))/

        # 語の末尾に残った助詞。「前章の」「画像の」は語の後ろに助詞が付いた断片
        FRAGMENT_TAIL = /[^ぁ-ん][のをがはにへでとやも]\z/

        # 数と単位（`1mm`・`2,894`・`50%`・`1 語`）。値であって語ではない
        MEASUREMENT = /\A[\d.,]+\s*(?:[a-zA-Z%]+|[ぁ-んァ-ヶ一-龯]{1,2})?\z/

        # 数字・カンマ・スラッシュだけの語（「31, 30,」「1/239」「355/113」）。値であって語ではない。
        # 分数を索引に立てるなら、その式の名前（「マチンの公式」「密率」）の側
        NUMBERS_ONLY = %r{\A[\d.,\s/]+\z}

        # 数学の記号を含む語（「√n」「log₂n」「10⁻¹³」）。数式を地の文に書いた跡で、語ではない
        MATH_SYMBOL = /[√∑∏∫±×÷≤≥≠≈∞⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻₀₁₂₃₄₅₆₇₈₉]/

        # 本の構成の言葉。章末の演習や補遺は本の部品の名前で、索引から案内する語ではない。
        # 「付録」「コラム」は記法の名前として索引語にする本（本書）があるので含めない
        BOOK_STRUCTURE_WORDS = %w[補遺 演習 解答 章末問題 練習問題 まえがき あとがき はじめに おわりに].freeze

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
        # 「版」は同じものの書き方違い（「ビット演算版」「二次元配列版」）で、索引に立てるなら版を外した語
        PHRASE_SUFFIXES = %w[ならでは 向け 付き 済み ごと 版].freeze

        # 人に付ける敬称と、複数を表す接尾語。「まつもとさん」「書記たち」が候補になっていた
        # （spiral-ruby）。索引に立てるなら敬称を外した名前・語である
        PERSON_SUFFIXES = %w[さん 氏 くん 君 ちゃん 様 さま たち 達 ら].freeze

        # 末尾の句を作る接尾語と、人に付ける接尾語を外す（「Apple Books 向け」→「Apple Books」・
        # 「書記たち」→「書記」）
        def without_okurigana_suffix(nouns)
          nouns = nouns.dup
          nouns.pop while nouns.size > 1 && nouns.last[2] == '接尾' &&
                          (PHRASE_SUFFIXES.include?(nouns.last[0]) || PERSON_SUFFIXES.include?(nouns.last[0]))
          nouns
        end

        # 範囲や程度を表す語。名詞の連続をここで切る。「小数点以下」「誤差以内」が候補になり、
        # 途中にあれば「0 以上 1 未満」「小数点以下3桁程度」までつながっていた（spiral-ruby）。
        # IPADIC の品詞はまちまち（以下は非自立、未満は接尾、以降は副詞可能、付近は一般）なので、
        # 品詞でなく綴りで見る
        RANGE_WORDS = %w[以下 以上 未満 以内 以外 以降 以前 以後 以来 程度 前後 付近 同士 どうし].freeze

        # 1 行ぶん。行ごとに解析するのは、名詞連続が行をまたいでつながらないようにするため
        def each_noun_sequence_in_line(mecab, line)
          current_nouns = []
          mecab.parse(line) do |node|
            if node.is_eos?
              yield current_nouns
              current_nouns = []
              next
            end

            pos, pos_detail, pos_detail2 = node.feature.split(',')
            # 直前に空白があったか（rlength は前の空白を含む長さ）。連結で空白を
            # 落とすと「閲覧用 PDF」が「閲覧用PDF」になり、本文と一致しなくなる。
            # 細分類の 2 段目は助数詞の見分けに使う（quantity?）
            token = [node.surface, node.rlength > node.length, pos_detail, pos_detail2]

            # 空白の後に置かれた記号だけの名詞（IPADIC は `/` を名詞とする）は連続を切る。
            # インラインコードを消した「`error` / `warn` / `info`」の跡が「/ / /」という候補に
            # なっていた。空白を挟まない記号は語の一部（`Re:VIEW`・`Node.js`）なので残す。
            # 範囲を表す語（RANGE_WORDS）でも切る
            if pos == '名詞' && !(token[1] && !node.surface.match?(/[\p{L}\p{N}]/)) && !RANGE_WORDS.include?(node.surface)
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
          strip_math(heading).gsub(/`[^`]*`/, ' ').gsub(/(?<![\w.])@[\w:.-]+/, ' ').delete('*')
        end

        # 単独の名詞として見出しから拾う品詞（MeCab の細分類）。
        # 見出しには「指摘」「検査」「修正」のような動作の名詞（サ変接続）や「無効」「推奨」の
        # ような形容動詞の語幹も多く、これらは節の話題ではなく節の中でする作業を表す
        HEADING_SINGLE_NOUN_KINDS = %w[一般 固有名詞].freeze

        # 見出しに 1 語で出ても、節の話題ではない位置の言葉（「### 後ろから挿入する」）
        POSITION_WORDS = %w[前 後ろ 上 下 左 右 横 隣 奥 手前 端 途中 外側 内側].freeze

        # 見出しから拾ってよい語か。短い語も通すが、ひらがなだけの語（「とき」「もの」）と
        # 1 字の語（「章」「図」）は語として弱いので落とす
        def heading_term?(term, nouns)
          return false if nouns.size == 1 && !HEADING_SINGLE_NOUN_KINDS.include?(nouns.first[2])
          return false if nouns.size == 1 && POSITION_WORDS.include?(term)
          return false if quantity?(nouns)

          term.length >= 2 && term.match?(/[ァ-ヶ一-龯A-Za-z]/) && valid_term?(term)
        end

        # 数と助数詞だけの並び（「三年」「二倍」「三年目」）。量の表現であって語ではない。
        # 見出しの語は 2 字でも拾うので、「### 三年で5万倍という青天井」から「三年」が候補に
        # なっていた（数字で書いた「5万倍」は MEASUREMENT が落とすが、漢数字は素通りしていた）。
        # 助数詞が 1 字のときに限る——「十進数」「二進数」も MeCab では 数＋助数詞（進数）になる。
        # 助数詞の後ろに続いてよいのは、量の表現を作る接尾語（QUANTITY_SUFFIXES）だけ。
        # 何でも許すと「二段組」「千分率」「十六進法」「一次式」まで落ちた。
        # 2 字以上でも量にしか使わない助数詞（COUNTER_WORDS）は数える。
        # @param nouns [Array<Array>] [表層形, 直前に空白があったか, 細分類, 細分類 2]
        def quantity?(nouns)
          # 「三つめ」は文脈で 三・つ・め／三・つめ／三つ・め と切り方が揺れる。和語の数え方を
          # 1 語で持つ形（三つ）も、数と助数詞の組として扱う
          return false if nouns.empty?
          return nouns.drop(1).all? { QUANTITY_SUFFIXES.include?(it[0]) } if nouns.first[0].match?(NATIVE_COUNT)

          counter, *rest = nouns.drop_while { numeral?(it) }
          return false if counter.nil? || counter.equal?(nouns.first)

          counter?(counter) && rest.all? { QUANTITY_SUFFIXES.include?(it[0]) }
        end

        # 数か。「数百桁」の「数」は、文脈によって MeCab が普通の名詞（かず）と切るので、
        # 「数」「何」「幾」は品詞にかかわらず数とみなす（一つでも取りこぼすと候補になる）
        def numeral?(token) = token[2] == '数' || %w[数 何 幾].include?(token[0])

        def counter?(token)
          (token[3] == '助数詞' && token[0].length == 1) || COUNTER_WORDS.include?(token[0])
        end

        # 和語の数え方を 1 語で持つ形（「一つ」「三つ」「幾つ」）
        NATIVE_COUNT = /\A[一二三四五六七八九十幾何]つ\z/

        # 2 字以上でも量にしか使わない助数詞。「つめ」は「三つめ」を MeCab が 三＋つめ（一般）と切るため
        COUNTER_WORDS = %w[箇所 ヶ所 か所 カ所 回り 種類 通り 時間 世紀 文字 段階 つめ つ目].freeze

        # 数と助数詞の後ろに付いても量の表現のままの接尾語（「三年目」「一年後」）。
        # 「以上」「程度」は RANGE_WORDS が名詞の連続を切るので、ここには要らない
        QUANTITY_SUFFIXES = %w[目 め 間 後 前 分 あたり ごろ 頃 ぶり あまり 余り 足らず
                               越し 近く ずつ おき ごと 毎 じゅう 中 弱 強 半].freeze

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
          return if quantity?(nouns)
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

        # 番号付けの呼び名。日本語の言葉の後ろに番号が付いた語（「課題38」「ステップ 2」「図3」）と、
        # それに助詞で続けた語（「課題165のポーカー」— 見出しの「## 課題165のポーカー」から拾われる）。
        # 助詞で続く形に限るのは、番号の後ろに言葉が直に付いた「第2正規形」が一つの語だから。
        # 言葉に英字を含むもの（`UTF-8`・`HTML5`・`ES2015`）は製品や規格の名前なので対象外。
        # 言葉は最短で取る——「課題3の図2」の言葉は「課題」。
        # 番号には英大文字 1 字も含める（「補遺A」「付録B」）
        LABEL_NUMBER = /(?:[0-9０-９]+|[A-ZＡ-Ｚ](?![A-Za-z]))/
        NUMBERED_LABEL = /\A(?<label>[^A-Za-z]*?[ぁ-んァ-ヶ一-龯])[ \t]?#{LABEL_NUMBER}(?:[のでをはがとにも].*)?\z/

        # 同じ言葉に違う番号がこの数以上付いていれば、番号付けとみなす
        NUMBERED_LABEL_MIN_VARIANTS = 3

        # 置かれ方で分かる非語を候補から外す。どれも語の形からは判別できない。
        #
        # 表の列の値: 早見表の「解説章」列に「拡張リファレンス」が 39 回並ぶと、
        #   その語は本の中の索引語のように数えられる。セルの中身がその語だけという
        #   出現が並ぶのは、列の値（ラベル）の特徴である。
        # 定型句: 「表示結果は次のようになります」の「表示結果」は、21〜23 章で 70 回
        #   同じ文の中に出る。語の使われ方が 1 通りしかないのは、説明ではなく決まり文句。
        # 番号付けの呼び名: 「課題38」は MeCab が「課題」「38」の名詞の連続として拾い、
        #   その章の見出し（「## 課題38　銀行口座クラス」）に立ち、その章に集まるので、
        #   一つずつ見ると専門用語と同じ形をしている（spiral-ruby で 103 語が候補に並んだ）。
        #   「課題1」〜「課題180」と番号違いが並ぶことで初めて、番号付けだと分かる。
        def discard_structural_terms!
          labels = table_cell_labels
          @scoring.terms.each do |term|
            @scoring.discard(term) if table_label?(term, labels[term]) || boilerplate?(term) ||
                                      enclosed?(term) || numbered_label?(term)
          end
        end

        # 本文で、同じ言葉に違う番号が NUMBERED_LABEL_MIN_VARIANTS 以上付いているか。
        # 候補でなく本文で数えるのは、番号違いの多くが候補に上がらない（1 回しか出ない）ため
        def numbered_label?(term)
          label = term[NUMBERED_LABEL, :label] or return false

          numbered_label_variants(label) >= NUMBERED_LABEL_MIN_VARIANTS
        end

        # 言葉ごとの、本文に出る番号の種類の数（「課題」なら 180）
        def numbered_label_variants(label)
          (@numbered_label_variants ||= {})[label] ||= prose_documents.flat_map do
            it.scan(/#{Regexp.escape(label)}[ \t]?(#{LABEL_NUMBER})(?![0-9０-９])/).flatten
          end.uniq.size
        end

        # より長い候補の中にしか出てこない語か。「ギリシャ」は本文の 3 回とも「ギリシャ文字」の
        # 一部で、カタカナの並びとして切り出されただけだった（改善案 #99）。長いほうの候補が
        # 同じ回数以上出ていれば、短いほうが単独で使われた箇所はない。
        #
        # 長い候補が複数に分かれることもある。「UTF」の 18 回は「UTF-8」17 回と「UTF-16」1 回で、
        # どちらか一つでは届かない（spiral-ruby）。複数で覆う場合は、長い候補がどれも短い語に
        # 番号を付けただけの形（版や規格の違い）のときだけ外す。どんな長い候補でも数えると、
        # 「ベクトルb」「固有ベクトル」が「ベクトル」を、「将棋盤バージョン」のような断片が
        # 「バージョン」を覆い、それ自体が索引に立つ概念の語まで消していた。
        # カタカナの名前が、どの長い候補でも後ろに語を従える形（「グレゴリオ暦」「ハフマン符号」
        # 「適応型ハフマン符号」）も外す。名前だけでは索引から何を引くのか定まらず、長い語のほうが
        # 引く語になる。名前で終わる形（「固有ベクトル」）が混ざれば、短いほうも語として残す。
        # そのうえで長い候補の出現を伏せ、短いほうが単独で残るかを本文で数える
        def enclosed?(term)
          tf = term_frequencies[term].to_i
          return false if tf.zero?

          pattern = occurrence_pattern(term)
          longers = longer_terms.select do |longer, _|
            longer.length > term.length && longer.include?(term) && longer.match?(pattern)
          end
          return true if longers.any? { |_, longer_tf| longer_tf >= tf }

          variant = /\A#{Regexp.escape(term)}[ \-]?\d+(?:\.\d+)*\z/
          heads = term.match?(NAME_ONLY) && longers.keys.none? { it.end_with?(term) }
          longers = longers.select { |longer, _| heads || longer.match?(variant) }
          return false if longers.sum { |_, longer_tf| longer_tf } < tf

          covering = Regexp.union(longers.keys.sort_by { -it.length }.map { occurrence_pattern(it) })
          # 伏せる文字は NUL。本文に現れず、語の一部にもならない
          prose_documents.none? { it.gsub(covering, "\u0000").match?(pattern) }
        end

        # カタカナだけの名前（「グレゴリオ」「チュドノフスキー」）。英字の略語（HTTP・ISO・IoT）は、
        # 長い語の頭に立つだけでも単独で引かれる概念なので対象外（UTF は番号付きの形の判定で外れる）
        NAME_ONLY = /\A[ァ-ヶー・]+\z/

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
          # 続きに数式の跡がある出現は数えない。中身の違う数式（`$\pi$`・`$1$`）がどれも同じ印に
          # なるので、「積分区間の長さは $\pi$ ですから」が決まり文句に見えてしまう
          tails = prose_documents.flat_map { it.scan(pattern).flatten }.reject { it.include?(MATH_GAP) }
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

          # 数式。中身は LaTeX の命令と記号で、索引から案内する本文ではない。下の `{…}` の
          # 除去より前に外す——後にすると `$\dfrac{\pi}{4}$` が `$\dfrac$` になり、
          # `$\pi`・`pi$` が候補に並んでいた（spiral-ruby で 131 語）。改行は残す
          text = strip_math(text)

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

          # 振り仮名 {通日|つうじつ} は親文字へ戻す。下の属性指定の除去で丸ごと消すと、
          # 「### ユリウス{通日|つうじつ}」が「ユリウス」単独の出現に見えていた
          text.gsub!(/\{([^{}|\n]+)\|[^{}\n]+\}/, '\1')

          # 画像の属性指定 {width=20%} など
          text.gsub!(/\{[^}]*\}/, ' ')

          # Markdownリンク記法の URL 部分を除外
          text.gsub!(/\]\([^)]+\)/, '] ')

          # 裸 URL と脚注の定義行の URL。`https://rubyinstaller.org/` から「rubyinstaller」を候補にしない
          text = Masking.strip_urls(text)

          # インラインコード
          text.gsub!(/`[^`]+`/, ' ')

          # 連続する空白を 1 つに。**改行は残す**——行をまたいで語がつながらないように
          # （見出し「Technical Terms」と次の行の「HTML」が「Technical Terms HTML」になる）
          text.gsub!(/[ \t]*\n\s*/, "\n")
          text.gsub!(/[ \t]+/, ' ')

          text
        end

        # 数式（4 種類の区切り。解釈の正典は MathDelimiters）を MATH_GAP に置き換える。
        # 空白にすると両側の名詞が空白越しにつながり、「誤差を $10^{-10}$ 未満」から
        # 「誤差 未満」が候補になっていた。ディスプレイ数式は行をまたぐので、改行の数だけは残す
        def strip_math(text)
          MathDelimiters::ALL.reduce(text) do |acc, pattern|
            acc.gsub(pattern) { "#{MATH_GAP}#{"\n" * it.count("\n")}" }
          end
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
          return false if term.match?(NUMBERS_ONLY) || term.match?(MATH_SYMBOL) || BOOK_STRUCTURE_WORDS.include?(term)

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
