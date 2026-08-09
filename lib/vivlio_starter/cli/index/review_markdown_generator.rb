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
      # 旧ファイル名との互換性のため、両方をチェック
      REVIEW_FILE = '_index_glossary_review.md'
      LEGACY_REVIEW_FILE = '_index_review.md'

      # 今回走査しなかった章から拾った抜粋であることを示す注記。
      # 章を指定して実行すると（`vs index:auto 33`）指定外の章の抜粋が混ざるため、
      # どこから来た文章なのかを言う。表示専用で、apply のパース時に剥がされる。
      OUT_OF_SCOPE_NOTE = '（走査対象外）'

      # セクションの見出し。走査範囲の境目に使うので綴りを 1 箇所に置く
      TERMS_SECTION = '## 1. 登録済み用語の確認'
      HIGH_SECTION = '## 2. 推奨候補'
      REJECTED_SECTION = '## 4. 除外済みリスト'

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
        File.exist?(REVIEW_FILE) || File.exist?(LEGACY_REVIEW_FILE)
      end

      # 実際のレビューファイルパスを取得
      # @return [String]
      def review_file_path
        return REVIEW_FILE if File.exist?(REVIEW_FILE)
        return LEGACY_REVIEW_FILE if File.exist?(LEGACY_REVIEW_FILE)

        REVIEW_FILE
      end

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
        boundary ? IndexCommands::TermLine.scan(content[boundary..]) : []
      end

      # 用語集として承認された候補を抽出（[g], [ig], [gi] マーク）
      # 説明文も抽出する
      # @return [Array<Hash>] 用語集候補のリスト（definition 付き）
      def parse_glossary_approved
        return [] unless exists?

        content = File.read(review_file_path, encoding: 'utf-8')
        approved = []

        # [g], [ig], [gi] を用語集として抽出
        parse_terms_with_definitions(content).each do |entry|
          flag = entry[:flag]
          next unless flag.match?(/^(?:g|ig|gi)$/)

          approved << {
            'term' => entry[:term],
            'yomi' => entry[:yomi],
            'definition' => entry[:definition],
            'contexts' => entry[:contexts]
          }
        end

        approved
      end

      # 後方互換性のため parse_approved も維持（索引用）
      # @return [Array<Hash>] 承認済み候補のリスト
      def parse_approved
        parse_index_approved
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
                                      .map { { 'term' => it.term, 'yomi' => it.yomi, 'flag' => it.flags } }
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
              if current_line.match?(MAIN_REFERENCE_PREFIX)
                i += 1
                next
              end

              # 出現箇所行: "  - chapter: context"
              # MatchData を受けてから読む——`Regexp.last_match` のままだと、
              # 章名を整える sub がその場で $~ を上書きし、続けて読む文脈が
              # nil になる。辞書の contexts が軒並み空だったのはこれが原因。
              if (occurrence = current_line.match(/^  - ([^:]+): (.+)/))
                # 表示用の注記は辞書へ戻さない（旧版の「（catalog 外）」も剥がす）
                chapter = occurrence[1].sub(/#{OUT_OF_SCOPE_NOTE}\z|（catalog 外）\z/o, '')
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

      # Markdown形式を構築
      # @param data [Hash] セクション別データ
      # @return [String] Markdown文字列
      def build_markdown(data)
        terms = data[:terms] || []
        high_candidates = data[:high_candidates] || []
        low_candidates = data[:low_candidates] || []
        rejected = data[:rejected] || []

        <<~MARKDOWN
          # 索引・用語集レビュー
          ※ フラグ: [i]=索引のみ、[g]=用語集のみ、[ig]=両方、[r]=棄却、[-i]=索引から除外、[-g]=用語集から除外
          ※ 読みの修正は ( ) 内を編集。用語集の説明文は空行の後にインデントして記述。
          ※ フラグの `m` は主要参照（その語を腰を据えて説明している章）です。[im33] なら 33 章。
             複数章は [im21,22]。索引でその章の説明箇所が太字＋先頭に並びます。
          ※ `m?` が付いているものは機械が推測した候補です。そのままだと採用されます。
             違う章なら数字を書き換え、指定したくなければ `m?33` ごと消してください。
          ※ 章名や節まで指すときは、用語の下に `- 主要参照: 21#Markdown とは` と書きます
             （子行がフラグ欄より優先されます）。
          ※ 一度外した語は候補（2・3 節）には現れず、末尾の 4 節「除外済みリスト」#{rejected_note(rejected)}に集まります。
             やっぱり戻すときは、そこで [i] / [g] / [ig] を入れて `vs index:apply`。

          #{build_terms_section(terms)}

          #{build_high_candidates_section(high_candidates)}

          #{build_low_candidates_section(low_candidates)}

          #{build_rejected_section(rejected)}
        MARKDOWN
      end

      # 凡例に添える除外済みの語数。2,000 行を超えるファイルなので、末尾に
      # 何語あるかを先頭で言っておかないと「無くなった」と読まれる。
      def rejected_note(rejected)
        rejected.empty? ? '' : "（現在 #{rejected.size} 語）"
      end

      # 1. 登録済み用語セクション
      def build_terms_section(terms)
        # 無効な用語をフィルタリング（手動マークアップは除外しない）
        valid_terms = terms.reject { |t| should_filter_term?(t) }
        section = "## 1. 登録済み用語の確認 (Terms: #{valid_terms.size}語)\n\n"

        return "#{section}登録済みの用語はありません。\n" if valid_terms.empty?

        common, rest = valid_terms.partition { it['common_term'] }
        review, ordinary = rest.partition { it['review_candidate'] }
        section += build_common_terms_subsection(common)
        section += build_review_terms_subsection(review)
        section += "### 登録語 (#{ordinary.size}語)\n\n" if common.any? || review.any?
        sort_by_label_and_appearance(ordinary).each { section += build_term_line(it, checked: true) }
        section
      end

      # 見直し候補（順位が目安語数の外に出た登録語）のサブセクション。
      #
      # この一覧が無いと、著者は「見直し候補 61 件」という**件数だけ**を告げられ、
      # どの語のことか分からないまま終わる。外すべき語を見つける場はここにしかない。
      #
      # 一般語と違って既定は現状維持（[i] のまま）にする。順位が低いことは
      # 「索引に要らない」を意味しない——章を絞った本では専門語でも出現が少ない。
      # 判断材料（順位が外に出たという事実）だけ示して、決めるのは著者に委ねる。
      def build_review_terms_subsection(review)
        return '' if review.empty?

        <<~HEADER + sort_by_label_and_appearance(review).map { build_term_line(it, checked: true) }.join
          ### 見直し候補（#{review.size}語）

          登録済みですが、未登録の候補と同じ土俵でスコア順に並べると、目安語数の外へ
          出た語です。索引としての優先度が低いか、より適切な語（「カラー」に対する
          「アクセントカラー」のような、長くて意味の絞られた語）が別にあるかもしれません。

          - そのままにする場合: [i] のまま `vs index:apply`
          - 索引から外す場合: [-i] にする
          - 二度と候補に出したくない場合: [r] にする（除外済みリストへ移ります）

        HEADER
      end

      # 一般語（広く散らばりすぎている語）のサブセクション。
      #
      # セクション番号を増やさないのが要点——既存のパーサは
      # 「## 4. 除外済みリスト」を境界に使っているので、`## 5.` を足すと
      # そこまでの解釈がずれる。`###` の入れ子なら影響しない。
      #
      # 行の書式は通常の登録語と同一にする。`- [-i] ` と `**用語** (読み)` の
      # 間に何かを差し込むと、7 つのパーサの正規表現が軒並みマッチしなくなる。
      # 追加情報は行末（スコアと同じ位置）へ置く。
      def build_common_terms_subsection(common)
        return '' if common.empty?

        <<~HEADER + common.map { build_term_line(it, checked: true) }.join
          ### 一般語（索引から外すことを推奨・#{common.size}語）

          本の広い範囲に散らばっている語です。索引から引いても読者が「どこを読めばよいか」を
          判断できないため、外すことを推奨します。

          分かれ目は**その語を腰を据えて説明している箇所があるか**です。

          - **説明箇所がある**（Markdown の解説書における「Markdown」など）
            → [i] に戻し、`[im21]` か子行 `- 主要参照: 21` でその箇所を指してください。
              索引で太字＋先頭に並び、「まずここを読めばよい」が読者に伝わります
          - **説明箇所がない**（書名・副題そのものなど、本全体が主題である語）
            → [-i] のまま。指す先のない主要参照は目印になりません。
              フラグに `g` があれば用語集には残るので、ページ番号を並べる代わりに
              定義文で説明を届けられます
          - **どちらでもない一般語**
            → [-i] のまま `vs index:apply`

        HEADER
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
        return true if term_text.match?(%r{^[&|!<>=+\-*/%^~]+$})

        # HTMLタグ風 (<h1>, </h1>, <!DOCTYPE> など)
        return true if term_text.match?(%r{^</?[a-zA-Z!]})

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
      #
      # ここだけ文脈を出さない。目安語数の外に出た語を**眺める**場所であって、
      # 一語ずつ判断する場所ではない——迷うほどの語なら順位が上がって推奨候補に
      # 現れる。文脈を並べると推奨候補と同じ密度になり、「これも全部見なければ」
      # と読めてしまううえ、後ろの除外済みリストまで遠くなる。
      def build_low_candidates_section(candidates)
        section = "## 3. 一般候補 (Low Candidates: #{candidates.size}語)\n"
        section += "※ 目安語数の外に出た語です。眺めて、目に留まったものだけ [i] にしてください。\n"
        section += "   一覧性を優先して出現箇所は省いています。\n\n"

        if candidates.empty?
          section += "一般候補はありません。\n"
        else
          sorted = sort_by_label_and_appearance(candidates)
          sorted.each { section += build_candidate_line(it, context_limit: 0) }
        end

        section
      end

      # 4. 除外済みリストセクション（Candidatesと同様の形式、rejected_atでラベル判定）
      def build_rejected_section(rejected)
        section = "## 4. 除外済みリスト (Rejected: #{rejected.size}語)\n"
        section += "※ 復帰させたいものは [i], [g], [ig] を入れると索引・用語集に直接登録されます。\n\n"

        if rejected.empty?
          section += "除外済みの用語はありません。\n"
        else
          # ラベルと出現順でソート
          sorted = sort_rejected_by_label(rejected)
          sorted.each { |item| section += "#{build_rejected_line(item)}\n" }
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
        definition = term['definition']
        # 登録先に基づいてフラグを決定
        checkbox = determine_registration_flag(term, checked)

        line = "- #{checkbox}"
        line += " `#{label}`" if label
        line += " **#{term_text}** (#{yomi})"
        # 手動マークアップは「[手動登録]」、それ以外はスコア表示。
        # スコアは辞書に持たない派生データなので、走査した章に出てこない語では nil になる。
        # ただし「どの章にも無い死語」と「今回走査しなかった章にはある語」は別物で、
        # 前者は外す判断へ、後者は残す判断へ導く——文脈が拾えたかどうかで見分ける。
        if source == 'manual_markup'
          line += ' - [手動登録]'
        elsif score
          line += " - スコア: #{score.round(1)}"
        elsif checked
          line += Array(term['contexts']).any? ? ' - [走査対象外の章に出現]' : ' - [原稿に出現しません]'
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
          # 今回走査しなかった章の抜粋は注記する（表示のみ・apply のパースで剥がされる）
          chapter = "#{chapter}#{OUT_OF_SCOPE_NOTE}" if ctx['out_of_scope']
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
        # 一般語は「外す」を既定にして提示する。著者は残したければ [i] へ戻す（R5）
        return '-i' if term['common_term']

        in_index = term['in_index'] != false # 既定はtrue（後方互換性）
        in_glossary = term['in_glossary'] == true

        if in_index && in_glossary then 'ig'
        elsif in_glossary then 'g'
        else 'i'
        end
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

        line = '- [ ]'
        line += " `#{label}`" if label
        line += " **#{term}** (#{yomi}) - スコア: #{score.round(1)}\n"

        # 1 行に詰めるときは語の間の空行も置かない（詰めることが目的なので）
        return line if context_limit.zero?

        Array(candidate['contexts']).first(context_limit).each do |ctx|
          chapter = ctx['chapter'] || '不明'
          line += "  - #{chapter}: #{extract_context(ctx['context'])}\n"
        end

        "#{line}\n"
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

        context_width = @config[:context_width]

        if text.length <= context_width * 2
          text
        else
          # 形態素境界を考慮した切り出しは抽出時に済んでいるため、ここでは単純にトリム
          text[0..(context_width * 2)]
        end
      end
    end
  end
end
