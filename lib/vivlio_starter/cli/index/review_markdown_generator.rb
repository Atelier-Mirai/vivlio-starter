# frozen_string_literal: true

# ================================================================
# Class: ReviewMarkdownGenerator
# ----------------------------------------------------------------
# 責務:
#   _index_glossary_review.md の生成・解析を担当
#   仕様書 index_glossary_spec.md に準拠
#
# 主要メソッド:
#   - generate!: レビュー用Markdownを生成（4セクション構成）
#   - parse_index_approved: 索引として承認された候補を抽出
#   - parse_glossary_approved: 用語集として承認された候補を抽出
#   - parse_rejected: リジェクト候補を抽出
#   - parse_unreject: Rejectedセクションで解除された候補を抽出
#
# フラグ体系:
#   - [i]: 索引のみ
#   - [g]: 用語集のみ（説明文必須）
#   - [ig]/[gi]: 索引と用語集の両方
#   - [r]: 両方からリジェクト
#   - [-i]: 索引からのみ削除
#   - [-g]: 用語集からのみ削除
#   - [ ]: 保留（次回再表示）
# ================================================================

require 'fileutils'
require 'time'
require_relative '../common'
require_relative 'term_line'

module VivlioStarter
  module CLI
    class ReviewMarkdownGenerator
      REVIEW_FILE = '_index_glossary_review.md'

      # 今回走査しなかった章から拾った抜粋であることを示す注記。表示専用で、
      # apply のパース時に剥がされる（章名の一部と誤って辞書へ戻さないため）。
      #
      # 2 種類あるのは著者の判断が変わるから。走査対象外は「今回指定しなかっただけ」で
      # 本には載る章。catalog 未登録は本に入らない章なので、その語には索引のページ番号が
      # 付かない——章を catalog へ戻すか、語を索引から外すかを決める必要がある。
      OUT_OF_SCOPE_NOTE = '（走査対象外）'
      OUTSIDE_CATALOG_NOTE = '（catalog 未登録）'
      # 旧版が書いた「（catalog 外）」も剥がす（レビューファイルは版をまたいで残る）
      CONTEXT_NOTES = [OUTSIDE_CATALOG_NOTE, OUT_OF_SCOPE_NOTE, '（catalog 外）'].freeze

      # セクションの見出し。走査範囲の境目に使うので綴りを 1 箇所に置く
      TERMS_SECTION = '## 1. 登録済みの語'
      HIGH_SECTION = '## 2. 推奨する語'
      REJECTED_SECTION = '## 4. 棄却した語'
      ABSENT_SECTION = '## 5. 原稿に出てこない語'

      # 見出しの位置。**行頭に限る**のが要点——本文で見出し名に触れただけで
      # 境界がそこへ動き、以降の解釈がまるごとずれる。凡例に「4 節『除外済み
      # リスト』」と書こうとして実際に踏んだ罠で、9 つの読み取りが一斉に壊れた。
      # @return [Integer, nil] 見出しの開始位置。無ければ nil
      def self.section_index(content, heading)
        content.match(/^#{Regexp.escape(heading)}/)&.begin(0)
      end

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

      # 実際のレビューファイルパスを取得
      # @return [String]
      def review_file_path = REVIEW_FILE

      # 索引として承認された候補を抽出（[i], [ig], [gi], [x] マーク）
      # @return [Array<Hash>] 索引候補のリスト
      def parse_index_approved
        term_lines.select(&:index?).map { { 'term' => it.term, 'yomi' => it.yomi } }
      end

      # レビューファイル全体の用語行。フラグの綴りは TermLine が唯一の定義元で、
      # ここから下のパーサはその判定（index? / reject_index? …）を使う。
      # @return [Array<TermLine>]
      def term_lines
        return [] unless exists?

        IndexCommands::TermLine.scan(File.read(review_file_path, encoding: 'utf-8'))
      end

      # いまの形式（4 つの節の見出し）か。古い形式のファイルを apply が読み違えないように見る
      def current_format?
        return false unless exists?

        content = File.read(review_file_path, encoding: 'utf-8')
        [TERMS_SECTION, REJECTED_SECTION].all? { self.class.section_index(content, it) }
      end

      # レビューファイルに行がある語の名前（全節）。apply がフラグを外してよいのは、
      # 著者が目にした語だけ（index-glossary-registration-spec.md §3.1.4）
      # @return [Array<String>]
      def listed_term_names = term_lines.map(&:term).uniq

      # 除外済みリスト（セクション 4）の手前までの用語行。
      # あちらは「復帰させるか」を問う別の場なので、承認・棄却の集計には混ぜない。
      def term_lines_before_rejected_section
        return [] unless exists?

        content = File.read(review_file_path, encoding: 'utf-8')
        boundary = self.class.section_index(content, REJECTED_SECTION)
        IndexCommands::TermLine.scan(boundary ? content[0...boundary] : content)
      end

      # 除外済みリスト（セクション 4）の用語行
      def term_lines_in_rejected_section
        return [] unless exists?

        content = File.read(review_file_path, encoding: 'utf-8')
        boundary = self.class.section_index(content, REJECTED_SECTION)
        return [] unless boundary

        # 5 節（原稿に出てこない語）の手前まで。5 節には登録済みの語も並ぶので、
        # 4 節と同じに読むと「印の無い語＝棄却のまま」と取り違える
        finish = self.class.section_index(content, ABSENT_SECTION) || content.size
        IndexCommands::TermLine.scan(content[boundary...finish])
      end

      # 記録ごと消す語（`[DELETE]`。全節。index-glossary-registration-spec.md §3.3.3）
      # @return [Array<String>]
      def parse_deleted = term_lines.select(&:delete?).map(&:term).uniq

      # 用語集として承認された候補を抽出（[g], [ig], [gi] マーク）
      # 説明文も抽出する
      # @return [Array<Hash>] 用語集候補のリスト（definition 付き）
      def parse_glossary_approved
        return [] unless exists?

        content = File.read(review_file_path, encoding: 'utf-8')
        approved = []

        # 用語集に載せる印（[g]・[ig]・[-ig] など。読み方は TermLine）
        parse_terms_with_definitions(content).each do |entry|
          next unless entry[:line].glossary?

          approved << {
            'term' => entry[:term],
            'yomi' => entry[:yomi],
            'definition' => entry[:definition],
            'contexts' => entry[:contexts]
          }
        end

        approved
      end

      # リジェクト候補を抽出（[r], [-ig], [-gi] マーク）
      # @return [Array<Hash>] リジェクト候補のリスト
      def parse_rejected
        term_lines_before_rejected_section.select(&:reject_both?).map do |line|
          entry = { 'term' => line.term, 'yomi' => line.yomi, 'kind' => 'both' }
          entry['score'] = line.score if line.score
          entry
        end
      end

      # 索引のみリジェクト（[-i] マーク）を抽出
      # @return [Array<Hash>] 索引リジェクト候補のリスト
      def parse_index_rejected
        term_lines_before_rejected_section.select(&:reject_index?)
                                          .map { { 'term' => it.term, 'yomi' => it.yomi, 'kind' => 'index' } }
      end

      # 用語集のみリジェクト（[-g] マーク）を抽出
      # @return [Array<Hash>] 用語集リジェクト候補のリスト
      def parse_glossary_rejected
        term_lines_before_rejected_section.select(&:reject_glossary?)
                                          .map { { 'term' => it.term, 'yomi' => it.yomi, 'kind' => 'glossary' } }
      end

      # 除外済みリストで復帰マークが付いた候補を抽出（リジェクト解除＋直接登録）。
      # フラグをそのまま持ち帰り、索引・用語集への登録先の判断に使う。
      # @return [Array<Hash>] リジェクト解除候補のリスト（flag 付き）
      def parse_unreject
        term_lines_in_rejected_section.select(&:unrejecting?)
                                      .map { { 'term' => it.term, 'yomi' => it.yomi, 'flag' => it.kept_flags } }
      end

      # 除外済みリストの全項目を抽出（フラグ不問）。
      # apply 時に index_terms/glossary_terms からの除去と rejected への同期に使う。
      # @return [Array<Hash>] 全項目のリスト（flag 付き）
      def parse_rejected_section_all
        term_lines_in_rejected_section.map { { 'term' => it.term, 'yomi' => it.yomi, 'flag' => it.flags } }
      end

      # 主要参照の指定を抽出する（`- 主要参照: 21, 22` / `- main: 21-22`）。
      #
      # 著者が触るのはこのレビューファイルであって辞書 YAML ではない。用語集の
      # 説明文と同じく「子ブロックに書く」形に揃えてある——フラグ欄に数字を
      # 入れる案（`[igm21,22]`）は、閉じていたフラグの語彙を開いてしまい、
      # 7 つのパーサすべてに切り分け処理が要る（§R3）。
      #
      # 値は章トークン。`21` `21, 22` `21-22` のいずれも書ける（TokenResolver が解釈）。
      # 行が無ければ nil を返す——「指定なし」と「行を消した＝解除」を同じ扱いにする。
      #
      # @return [Hash{String => Array<String>, nil}] 用語 → 章トークンの配列
      # 子行の綴りはここだけで決める。出現箇所行（`  - 章名: 文脈`）と見分けが
      # つかない形なので、値の有無に関わらず弾ける前半を切り出しておく。
      MAIN_REFERENCE_PREFIX = /^\s*-\s*(?:主要参照|main)\s*[:：]/
      MAIN_REFERENCE_LINE = /#{MAIN_REFERENCE_PREFIX}\s*(?:`(?:NEW!|Today)`\s*)?(.+)$/

      # 見出し語の綴りを直す子行（`- 綴り: ラベル ID`。改善案 #103）。主要参照と同じく、
      # 空行を挟まずに用語行の下へ書く（空行の後の字下げは用語集の説明文になる）
      SPELLING_PREFIX = /^\s*-\s*綴り\s*[:：]/
      SPELLING_LINE = /#{SPELLING_PREFIX}\s*(.+)$/

      # 綴りを直す指定。全節から読む（登録済みの語は 1 節にも 5 節にも並ぶ）
      # @return [Hash{String => String}] いまの綴り → 新しい綴り
      def parse_spelling_changes
        return {} unless exists?

        term_blocks(File.read(review_file_path, encoding: 'utf-8')).filter_map do |term, body|
          spelled = body[SPELLING_LINE, 1]&.strip
          [term, spelled] if spelled && !spelled.empty? && spelled != term
        end.to_h
      end

      def parse_main_references
        return {} unless exists?

        content = File.read(review_file_path, encoding: 'utf-8')
        boundary = self.class.section_index(content, REJECTED_SECTION)
        search = boundary ? content[0...boundary] : content

        # まずフラグ欄（`[igm33]`）を読み、子行があればそちらで上書きする。
        # 章名や節指定のような長い値は子行にしか書けないので、後から書き足した
        # 細かい指定が勝つ形にしてある。
        result = IndexCommands::TermLine.scan(search).to_h { [it.term, it.main] }
        term_blocks(search).each do |term, body|
          line = body[MAIN_REFERENCE_LINE, 1]
          result[term] = split_chapter_tokens(line) if line
        end
        result
      end

      # 用語行とそれに続くインデント行を 1 ブロックとして切り出す。
      # 行単位で独立に scan する他のパーサと違い、用語と子項目の対応が要るため。
      def term_blocks(content)
        blocks = []
        current = nil
        content.to_s.lines.each do |line|
          if (parsed = IndexCommands::TermLine.parse(line))
            current = [parsed.term, +'']
            blocks << current
          elsif current && line.match?(/\A[ \t]+\S/)
            current[1] << line
          elsif line.strip.empty?
            next # 空行はブロックを切らない（説明文が続くことがある）
          else
            current = nil
          end
        end
        blocks
      end

      # `21, 22` `21-22` `21 22` のいずれも章トークンの配列にする。
      # 解決（番号 → basename）は TokenResolver の仕事なので、ここでは分割だけ。
      def split_chapter_tokens(text)
        text.split(/[,、\s]+/).map(&:strip).reject(&:empty?)
      end

      # 登録済み用語セクションで読みが変更された用語を抽出
      # @return [Array<Hash>] 読み変更された用語のリスト
      def parse_yomi_changes
        return [] unless exists?

        content = File.read(review_file_path, encoding: 'utf-8')
        start = self.class.section_index(content, TERMS_SECTION) or return []
        finish = self.class.section_index(content, HIGH_SECTION) || content.length

        IndexCommands::TermLine.scan(content[start...finish])
                               .select { it.index? || it.glossary? }
                               .map { { 'term' => it.term, 'yomi' => it.yomi } }
      end

      # 用語と説明文をパース
      # 出現箇所リストと説明文を区別して抽出
      # @param content [String] Markdown内容
      # @return [Array<Hash>] パース結果
      def parse_terms_with_definitions(content)
        results = []
        lines = content.lines
        i = 0

        while i < lines.size
          line = lines[i]

          # 用語行を検出（綴りの定義元は TermLine）
          if (parsed = IndexCommands::TermLine.parse(line))
            flag = parsed.flags
            term = parsed.term
            yomi = parsed.yomi

            i += 1
            contexts = []
            definition_lines = []
            in_definition = false

            # 次の用語行まで走査
            while i < lines.size && lines[i] !~ /^- \[/
              current_line = lines[i]

              # 主要参照の子行は著者の指定であって出現箇所ではない。綴りが
              # `  - ラベル: 値` で下の出現箇所行と同型なので、先に弾かないと
              # `chapter: 主要参照` という文脈が辞書へ入る。しかもレビューを
              # 往復するたび再出力・再取り込みされ、値が空へ潰れて残り続ける。
              if current_line.match?(MAIN_REFERENCE_PREFIX) || current_line.match?(SPELLING_PREFIX)
                i += 1
                next
              end

              # 出現箇所行: "  - chapter: context"
              # MatchData を受けてから読む——`Regexp.last_match` のままだと、
              # 章名を整える sub がその場で $~ を上書きし、続けて読む文脈が
              # nil になる。辞書の contexts が軒並み空だったのはこれが原因。
              if (occurrence = current_line.match(/^  - ([^:]+): (.+)/))
                # 表示用の注記は辞書へ戻さない
                chapter = occurrence[1].sub(/#{Regexp.union(CONTEXT_NOTES)}\z/o, '')
                contexts << { 'chapter' => chapter, 'context' => occurrence[2] }
                i += 1
                next
              end

              # 空行で説明文開始を判定
              if current_line.strip.empty?
                in_definition = true
                i += 1
                next
              end

              # インデントされた行は説明文
              definition_lines << Regexp.last_match(1) if in_definition && current_line =~ /^  (.+)/

              i += 1
            end

            results << {
              flag: flag,
              line: parsed,
              term: term,
              yomi: yomi,
              contexts: contexts,
              definition: definition_lines.join("\n").strip
            }
          else
            i += 1
          end
        end

        results
      end

      private

      # 設定を読み込み（index_glossary 共通設定 + index 個別設定をマージ）
      def load_index_config
        load_shared_config.merge(Common::CONFIG.index.to_h)
      end

      # 共通設定（index_glossary）を読み込み
      def load_shared_config
        Common::CONFIG.index_glossary.to_h
      end

      # Markdown形式を構築。節は 登録済み・推奨・残り・棄却 の 4 つ
      # （index-glossary-registration-spec.md §3.2。小節は立てない）
      # @param data [Hash] セクション別データ
      # @return [String] Markdown文字列
      def build_markdown(data)
        terms = data[:terms] || []
        high_candidates = data[:high_candidates] || []
        low_candidates = data[:low_candidates] || []
        rejected = data[:rejected] || []
        absent = data[:absent] || []

        <<~MARKDOWN
          # 索引・用語集レビュー
          ※ 印: [i]=索引、[g]=用語集、[ig]=両方、[ ]=未決定、[r]=棄却、[DELETE]=記録ごと消す
          ※ マイナスは直後の 1 文字にだけ掛かります。[-i]=索引から外す、[-g]=用語集から外す、[-ig]=索引から外して用語集には残す、[-i-g]=両方から外す（[r] と同じ）。どこにも載らなくなる語は棄却します。
          ※ 主要参照（その語を腰を据えて説明している章）は [im21] のように m と章番号で書きます。複数章は [im21,22]、付けない語は [i]。`m?21` は機械の推測で、そのまま apply すれば採用されます。
          ※ 読みは ( ) 内を書き換えます。
          ※ 用語の下には、空行を挟まずに次の子行を書けます。
            - 主要参照: … 主要参照を、章だけでなく節まで指す（例: `- 主要参照: 25#ラベルIDの扱い`）
            - 綴り: … 辞書に登録した語そのものの綴りを直す（例: 「ラベルID」を `- 綴り: ラベル ID` で「ラベル ID」に。読み・印・説明文・主要参照はそのまま残る。原稿に古い綴りがあれば、apply のときに直すか尋ねる）
          ※ 用語集の説明文は、空行の後に字下げして書きます。次は、子行と説明文を書いた例です。

              - [igm25] **ラベルID** (らべるID)
                - 主要参照: 25#ラベルIDの扱い
                - 綴り: ラベル ID
                - 25-cross-reference: 図・表・リストに「ラベルID」を付けてキャプションを記述する

                図・表・リスト・見出しに付ける識別名。キャプションの末尾に @id と書き、本文から参照する。

          #{build_terms_section(terms)}

          #{build_high_candidates_section(high_candidates)}

          #{build_low_candidates_section(low_candidates)}

          #{build_rejected_section(rejected)}

          #{build_absent_section(absent)}
        MARKDOWN
      end

      # 1. 登録済みの語。印は「いま辞書にどう登録されているか」を示し、そのまま apply すれば
      # 変わらない（§2.1）。小節を立てない代わりに、apply で変わる行を先に置く——
      # 外す印 [-i] の付いた一般語 → 推測 m? の付いた語 → それ以外
      def build_terms_section(terms)
        # 無効な用語をフィルタリング（手動登録は除外しない）
        valid_terms = terms.reject { |t| should_filter_term?(t) }
        section = "#{TERMS_SECTION}（#{valid_terms.size}語）\n"
        section += "※ いまの登録を印で示しています。そのまま `vs index:apply` すれば変わりません。変えたい語だけ [] の中を書き換えてください。\n"
        return "#{section}\n登録済みの語はありません。\n" if valid_terms.empty?

        removing, rest = valid_terms.partition { it['common_term'] && !confirmed_main?(it) }
        guessed, ordinary = rest.partition { it['main_suggested'] }
        section += "#{COMMON_TERM_GUIDE}\n" if removing.any?
        section += "\n"
        [removing, guessed, ordinary].each do |group|
          sort_by_label_and_appearance(group).each { section += build_term_line(it, checked: true) }
        end
        section
      end

      # 一般語（本の広い範囲に散らばる語）に外す印を付けた理由。一般語は「スコアが低い語」
      # ではなく「広く散らばる語」なので、スコアの話にしない（§3.2）
      COMMON_TERM_GUIDE = '※ 外す印 `[-i]`（用語集にも載っている語は `[-ig]`）が付いた語は、本の広い範囲に散らばっていて、索引から引いても説明箇所が分からない語です。' \
                          '次から候補に出さなくてよければ、このまま `vs index:apply` してください。' \
                          '索引に残したい語は `[i]` に（説明している章があれば `[im21]` に）してください。'

      # 用語をフィルタリングすべきかどうかを判定
      # 手動登録の用語は著者の意図があるためフィルタリングしない
      # @param term [Hash] 用語データ
      # @return [Boolean] フィルタリングすべきならtrue
      def should_filter_term?(term)
        # 手動登録は著者の意図があるのでフィルタリングしない
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
        return true if term_text.match?(%r{^[&|!<>=+\-*/%^~]+$})

        # HTMLタグ風 (<h1>, </h1>, <!DOCTYPE> など)
        return true if term_text.match?(%r{^</?[a-zA-Z!]})

        false
      end

      # 2. 推奨する語（目安の語数の内側に入る未登録語）
      def build_high_candidates_section(candidates)
        section = "#{HIGH_SECTION}（#{candidates.size}語）\n"
        section += "※ 目安の語数に入るほど重要なのに、まだ登録していない語です。採る語は `[m?61]` を `[im61]` のように書き換えてください（i を書き足す。用語集にも載せるなら `[igm61]`）。`m61` はその語を説明している章（主要参照）で、違う章なら数字を書き換え、付けないなら `[i]` にします。採らない語は、そのままにするか `[r]`（次から候補に出さない）にします。\n\n"
        return "#{section}推奨する語はありません。\n" if candidates.empty?

        sort_by_label_and_appearance(candidates).each { section += build_candidate_line(it) }
        section
      end

      # 3. 残りの語
      #
      # ここだけ文脈を出さない。目安語数の外に出た語を**眺める**場所であって、
      # 一語ずつ判断する場所ではない——迷うほどの語なら順位が上がって推奨する語に
      # 現れる。文脈を並べると推奨する語と同じ密度になり、「これも全部見なければ」
      # と読めてしまううえ、後ろの棄却した語まで遠くなる。
      def build_low_candidates_section(candidates)
        section = "## 3. 残りの語（#{candidates.size}語）\n"
        section += "※ 目安の語数の外に出た語です。眺めて、目に留まったものだけ `[m?61]` を `[im61]` のように書き換えてください（書き方は 2 節と同じ）。一覧性を優先して出現箇所は省いています。\n\n"
        return "#{section}残りの語はありません。\n" if candidates.empty?

        sort_by_label_and_appearance(candidates).each { section += build_candidate_line(it, context_limit: 0) }
        section
      end

      # 4. 棄却した語（Candidatesと同様の形式、rejected_atでラベル判定）
      def build_rejected_section(rejected)
        section = "#{REJECTED_SECTION}（#{rejected.size}語）\n"
        section += "※ 次から候補に出さない語です。戻すときは [i]・[g]・[ig] を入れてください。棄却した語は `vs index:export` で次の本へも持ち運べます（同じ語を本ごとに棄却し直さずに済みます）。\n\n"

        if rejected.empty?
          section += "棄却した語はありません。\n"
        else
          # ラベルと出現順でソート
          sorted = sort_rejected_by_label(rejected)
          sorted.each { |item| section += "#{build_rejected_line(item)}\n" }
        end

        section
      end

      # 5. 原稿に出てこない語。登録済みの語・使っていない語・棄却した語を 1 か所にまとめる
      # （index-glossary-registration-spec.md §3.3.1）。既定の印はどれも [ ] で、そのまま apply
      # すると、登録済みの語は索引・用語集から外れ（説明文のある語は使っていない語として残る）、
      # 使っていない語・棄却した語はそのまま。並びは apply で変わる登録済みの語を先に置く
      ABSENT_KINDS = %w[registered unused rejected].freeze

      def build_absent_section(absent)
        section = "#{ABSENT_SECTION}（#{absent.size}語）\n"
        section += "※ 原稿のどこにも出てこない語です。登録済みの語は、そのまま `vs index:apply` すると索引・用語集から外れます（説明文のある語は、使っていない語として残ります）。誤って登録した語は `[DELETE]` で記録ごと消せます。\n\n"
        return "#{section}原稿に出てこない語はありません。\n" if absent.empty?

        absent.sort_by { [ABSENT_KINDS.index(it['kind']), it['yomi'].to_s.downcase] }.each do |item|
          section += build_absent_line(item)
        end
        section
      end

      # 5 節の 1 行。行末に、いまの扱い（登録済みならその印）を添える
      def build_absent_line(item)
        status = case item['kind']
                 when 'registered'
                   "いまの登録: #{IndexCommands::TermLine.build(item['flags'].to_s, main: Array(item['main_tokens']))}"
                 when 'unused' then '使っていない語'
                 else '棄却した語'
                 end
        line = "- [ ] **#{item['term']}** (#{item['yomi'] || item['term']}) - [原稿に出現しません] - #{status}\n"
        definition = item['definition'].to_s.strip
        line += "\n#{definition.each_line.map { "  #{it.chomp}\n" }.join}" unless definition.empty?
        "#{line}\n"
      end

      # 用語行を構築（Termsセクション用）- Candidatesと同様の形式
      def build_term_line(term, checked: false)
        term_text = term['term']
        yomi = term['yomi'] || term_text
        label = determine_label(term)
        score = term['score']
        source = term['source']
        definition = term['definition']
        # 登録先に基づいてフラグを決定
        checkbox = determine_registration_flag(term, checked)

        line = "- #{checkbox}"
        line += " `#{label}`" if label
        line += " **#{term_text}** (#{yomi})"
        # 手動登録の語は「[手動登録]」、それ以外はスコア表示。
        # スコアは辞書に持たない派生データなので、走査した章に出てこない語では nil になる。
        # ただし「どの章にも無い死語」と「今回走査しなかった章にはある語」は別物で、
        # 前者は外す判断へ、後者は残す判断へ導く——文脈が拾えたかどうかで見分ける。
        if source == 'manual_markup'
          line += ' - [手動登録]'
        elsif score
          line += " - スコア: #{score.round(1)}"
        elsif checked
          line += absent_term_note(term)
        end
        # 追加情報は必ず行末へ。`- [-i] ` と `**用語** (読み)` の間に差し込むと
        # 7 つのパーサの正規表現が軒並みマッチしなくなる。
        line += " - 一般語: #{term['spread_text']}に出現" if term['spread_text']
        line += "\n"

        # 主要参照のうち、フラグ欄へ収まらない値（章名・節指定）は子行で書く。
        # 著者が編集する行なので、機械が出す文脈より先に置く。
        tokens = Array(term['main_tokens'])
        if tokens.any? && !IndexCommands::TermLine.in_flag?(tokens)
          proposal = term['main_suggested'] ? '`NEW!` ' : ''
          line += "  - 主要参照: #{proposal}#{tokens.join(', ')}\n"
        end

        # 文脈を最大2件表示（Candidatesと同様）
        contexts = term['contexts'] || []
        contexts.first(2).each do |ctx|
          chapter = ctx['chapter'] || '不明'
          # 走査しなかった章の抜粋は出どころを注記する（表示のみ・apply のパースで剥がされる）
          chapter += OUTSIDE_CATALOG_NOTE if ctx['outside_catalog']
          chapter += OUT_OF_SCOPE_NOTE if ctx['out_of_scope']
          context_text = extract_context(ctx['context'])
          line += "  - #{chapter}: #{context_text}\n"
        end

        # 用語集の定義がある場合は表示
        if definition.to_s.strip.length.positive?
          line += "\n"
          definition.to_s.each_line { |def_line| line += "  #{def_line}" }
          line += "\n" unless line.end_with?("\n")
        end

        "#{line}\n"
      end

      # 登録先に基づいてフラグを決定
      # @param term [Hash] 用語データ
      # @param checked [Boolean] チェック済みかどうか
      # @return [String] フラグ文字列
      # 主要参照は章番号だけならフラグ欄へ収める（R6）。
      # 語ごとに子行を足すと、110 語の索引で 110 行増えて一覧性が落ちる。
      # 章名や節指定のような長い値は子行に譲る（`[igm21#Markdown とは]` は読めない）。
      def determine_registration_flag(term, checked)
        return '[ ]' unless checked

        IndexCommands::TermLine.build(base_flag(term), main: Array(term['main_tokens']),
                                                       suggested: term['main_suggested'])
      end

      def base_flag(term)
        # 一般語は「外す」を既定にして提示する。著者は残したければ [i] へ戻す（R5）。
        # 用語集にも載っている語は [-ig]（索引から外し、用語集には残す）。g を印に含めないと、
        # 用語集に載っていることが行から読めない（index-glossary-registration-spec.md §3.4）。
        # ただし著者が主要参照を決めた語（`m21`。機械の推測 `m?` は含まない）は残す——
        # 説明箇所がある語は残す、という一般語の欄の基準そのものなので。外す印のまま
        # 出していたため、そのまま apply した Markdown・PDF が索引から外れていた（改善案 #99）
        return term['in_glossary'] == true ? '-ig' : '-i' if term['common_term'] && !confirmed_main?(term)

        in_index = term['in_index'] != false # 既定はtrue（後方互換性）
        in_glossary = term['in_glossary'] == true

        if in_index && in_glossary then 'ig'
        elsif in_glossary then 'g'
        else 'i'
        end
      end

      # 著者が決めた主要参照を持つか（機械の推測 `m?` は数えない）
      def confirmed_main?(term) = Array(term['main_tokens']).any? && !term['main_suggested']

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
        # 原稿のどこにも無い語は、登録語と同じ注記を添える。文脈もスコアも無い行が
        # 黙って並ぶと、出現箇所の表示が漏れたのか、語が消えたのか見分けられない
        line += ' - [原稿に出現しません]' if contexts.empty?
        line += "\n"

        contexts.first(2).each do |ctx|
          chapter = ctx['chapter'] || '不明'
          context_text = extract_context(ctx['context'])
          line += "  - #{chapter}: #{context_text}\n"
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
      # 候補行。`context_limit: 0` なら語だけの 1 行にする（一般候補で使う）。
      # 文脈は 1 語につき 3 行を占め、311 語ならそれだけで 1,100 行——ファイルの
      # 半分になり、末尾の除外済みリストが埋もれていた。
      def build_candidate_line(candidate, context_limit: 2)
        term = candidate['term']
        yomi = candidate['yomi'] || term
        score = candidate['score'] || 0
        label = determine_label(candidate)

        # 主要参照の推測があれば `[m?95]`。採るときは `[im95]` と i を書き足すだけで済む
        # （空白を残すと `[ m?95]` になり、書き換えるたびに空白を 1 字消す手間が増える）。
        # 推測が無ければ未決定の欄 `[ ]`
        main = candidate['main_tokens']
        flags = IndexCommands::TermLine.in_flag?(Array(main)) ? '' : ' '
        line = "- #{IndexCommands::TermLine.build(flags, main:, suggested: candidate['main_suggested'])}"
        line += " `#{label}`" if label
        line += " **#{term}** (#{yomi}) - スコア: #{score.round(1)}\n"

        # 1 行に詰めるときは語の間の空行も置かない（詰めることが目的なので）。ただし説明文は
        # 出す——出さないまま [g] にすると、空の説明文で残しておいた説明文を上書きする
        if context_limit.zero?
          definition = candidate_definition(candidate)
          return definition.empty? ? line : "#{line}#{definition}\n"
        end

        Array(candidate['contexts']).first(context_limit).each do |ctx|
          chapter = ctx['chapter'] || '不明'
          line += "  - #{chapter}: #{extract_context(ctx['context'])}\n"
        end
        line += candidate_definition(candidate)

        "#{line}\n"
      end

      # 使っていない語を原稿に書き戻したときは、以前の説明文を添える。[g] にすれば
      # 書き直さずにそのまま戻る（index-glossary-registration-spec.md §3.3.2）
      def candidate_definition(candidate)
        definition = candidate['definition'].to_s.strip
        return '' if definition.empty?

        "\n#{definition.each_line.map { "  #{it.chomp}\n" }.join}"
      end

      # 走査した章に出てこない登録語の注記。行き先の違う 3 通りを言い分ける。
      #   死語               … 原稿のどこにも無い。語を外すか、綴りを直す
      #   catalog 未登録の章 … 本に入らない章にしか無い。章を戻すか、語を外す
      #   走査対象外の章     … 本には載る章にある。今回指定しなかっただけで、直す点は無い
      def absent_term_note(term)
        contexts = Array(term['contexts'])
        return ' - [原稿に出現しません]' if contexts.empty?
        return ' - [catalog 未登録の章に出現]' if contexts.all? { it['outside_catalog'] }

        ' - [走査対象外の章に出現]'
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

        # 長さはここで切らない。抜粋は ContextSnippet が文と読点の位置で詰めて作っており、
        # 字数で切り直すと「…自動化します。こ」のような半端な終わりに戻る（改善案 #99）
        context_text.to_s.gsub(/[\r\n]+/, ' ').strip
      end
    end
  end
end
