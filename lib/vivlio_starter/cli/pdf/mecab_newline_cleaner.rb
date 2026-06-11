# frozen_string_literal: true

require 'open3'

module VivlioStarter
  module PDF
    # MeCab を利用して PDF から抽出したテキストの不要改行を除去するクリーナー
    #
    # PDF からのテキスト抽出は組版上の行末で機械的に改行が入るため、
    # そのままでは文の途中で切れた読みにくいテキストになる。
    # 改行を「残す（段落・見出し・箇条書きの区切り）」か「除去する（行送りに
    # よる折り返し）」かを判定する必要があるが、日本語は英語と違い行末に
    # ハイフン等の手掛かりがないため、表層的な正規表現の判定に加えて
    # MeCab の形態素解析で行末・行頭の品詞を調べ、文が継続しているか
    # （行末が格助詞・活用途中の動詞、行頭が助詞など）を判断する。
    class MecabNewlineCleaner
      # 行頭にあれば前行から文が継続しているとみなす接続表現
      CONNECTIVE_PREFIXES = %w[が て と ので のに けど けれど けれども ものの し すると そして しかし でも].freeze
      LIST_MARKER_REGEX = /\A(?:[-*・]|\d+\.)/
      HEADING_REGEX = /\A#+/
      SECTION_HEADING_PREFIX_REGEX = /\A(?:第[一二三四五六七八九十百千0-9]+章|[♣♠♥♦]?\s*\d+(?:-\d+)*(?:\.)?)\z/
      SECTION_HEADING_REGEX = /\A(?:第[一二三四五六七八九十百千0-9]+章\s*.+|[♣♠♥♦]?\s*\d+(?:-\d+)*(?:\.)?\s*.+)\z/
      CHAPTER_HEADING_ONLY_REGEX = /\A第[一二三四五六七八九十百千0-9]+章\z/
      PUNCTUATION_REGEX = /[。．！？!?…]+[)）］】」』》]*\z/
      SMALL_KANA_START_REGEX = /\A[ゃゅょぁぃぅぇぉゎっァィゥェォヵヶッャュョヮ]/
      MIDWORD_END_REGEX = /[A-Za-z0-9ａ-ｚＡ-Ｚ０-９ァ-ヶぁ-ゖ一-龯ー々〆ヵヶ]\z/
      MIDWORD_START_REGEX = /\A[A-Za-z0-9ａ-ｚＡ-Ｚ０-９ァ-ヶぁ-ゖ一-龯ー々〆ヵヶ]/

      ENDING_AUXILIARIES = %w[です ます だ だった でした でしょう だろう である ません でしたら].freeze
      ENDING_PARTICLES = %w[ね よ よね ぞ さ わ かな かしら].freeze

      # MeCab の出力1行（表層形 + 素性）を保持する形態素トークン
      Token = Data.define(:surface, :base, :pos, :pos_detail1, :pos_detail2, :pos_detail3, :conj_type, :conj_form)

      def initialize(config = nil)
        cfg = config || {}
        @mecab_command = cfg[:mecab_command] || 'mecab'
        @mecab_cache = {}
      end

      # 抽出テキスト全体を整形して返すエントリポイント
      #
      # 空行（2連続以上の改行）で区切った「段落」と「ギャップ」を交互に処理する。
      # 段落内の改行は clean_paragraph で判定し、段落間のギャップも
      # 「実は文の途中（ページ跨ぎ等）」であれば結合する。
      def clean(text)
        str = normalize_pdf_extracted_text(text)
        return str if str.empty?

        segments = str.split(/(\n{2,})/, -1)
        rebuilt = []

        segments.each_with_index do |segment, idx|
          if idx.even?
            rebuilt << clean_paragraph(segment)
          else
            prev_block = rebuilt.last
            next_block = segments[idx + 1]

            if chapter_heading_gap?(prev_block, next_block)
              rebuilt << "\n"
            elsif chapter_title_gap?(rebuilt, prev_block, next_block)
              rebuilt << "\n"
            elsif should_merge_gap?(prev_block, next_block)
              # ギャップを完全に削除（結合）
            else
              rebuilt << segment
            end
          end
        end

        rebuilt.join
      end

      private

      attr_reader :mecab_command

      # 段落内の各行を「前行と結合」「見出しとして分離」「改行維持」に振り分ける
      def clean_paragraph(paragraph)
        body = paragraph.to_s
        lines = body.split("\n", -1).map(&:strip).reject(&:empty?)
        return body.strip if lines.length <= 1

        rebuilt = [lines.first.dup]
        lines[1..]&.each do |line|
          previous = rebuilt.last
          if split_heading?(previous, line)
            rebuilt[-1] = previous + line
          elsif heading_start_line?(line)
            rebuilt << '' unless rebuilt.last.empty?
            rebuilt << line.dup
          elsif keep_line_break?(previous, line)
            rebuilt << line.dup
          else
            rebuilt[-1] = previous + line
          end
        end

        rebuilt.join("\n")
      end

      # 2行の間の改行を残すべきか判定する（このクラスの中核ロジック）
      #
      # 判定順序が重要:
      #   1. 見出し・箇条書きなど構造上の区切り → 残す
      #   2. 単語の途中・小書き仮名・接続表現で始まる行 → 結合
      #   3. 句点で終わる行 → 残す
      #   4. ここまでで判定できない場合のみ MeCab で行末・行頭の品詞を調べる
      #      （外部プロセス呼び出しが高コストなため最後に回す）
      def keep_line_break?(current_line, next_line)
        return true if next_line.nil?
        return true if current_line.nil?

        curr = current_line.strip
        nxt = next_line.strip
        return true if curr.empty? || nxt.empty?
        return true if heading_line?(curr) || heading_line?(nxt)
        return true if list_line?(curr) || list_line?(nxt)
        return false if punctuation_only_line?(nxt)

        return false if midword_break?(curr, nxt)
        return false if small_kana_start?(nxt)
        return false if connective_start?(nxt)
        return true if punctuation_end?(curr)

        curr_tokens = mecab_tokens(curr)
        return true if curr_tokens.empty?

        next_tokens = mecab_tokens(nxt)

        last = curr_tokens.last
        return true if sentence_ending_particle?(last)
        return true if sentence_ending_auxiliary?(last)

        return false if mid_sentence_particle?(last)
        return false if conjugated_verb_or_adjective?(last)

        return false if next_tokens.any? && particle_or_auxiliary_start?(next_tokens.first)

        false
      end

      # 空行ギャップを挟んだ前後が実は連続した文かを判定する
      # （ページ跨ぎや図版を避けた組版で段落内に空行が入ることがあるため）
      def should_merge_gap?(previous_block, next_block)
        prev_line = previous_block.to_s.split("\n").last&.strip
        next_line = next_block.to_s.split("\n").find { !it.strip.empty? }&.strip

        return false if prev_line.to_s.empty?
        return false if next_line.to_s.empty?

        !keep_line_break?(prev_line, next_line)
      end

      # 「第N章」単独行とタイトル行の間のギャップか
      # （章扉では空行を1つの改行に縮めて「第N章\nタイトル」の形に整える）
      def chapter_heading_gap?(previous_block, next_block)
        chapter_heading_only_line?(single_non_empty_line(previous_block)) && title_line?(first_non_empty_line(next_block))
      end

      # 章タイトル行と本文の間のギャップか
      # （直前に「第N章」行がある場合のみ。タイトル直後の空行も1改行に縮める）
      def chapter_title_gap?(rebuilt, previous_block, next_block)
        previous_line = single_non_empty_line(previous_block)
        next_line = first_non_empty_line(next_block)
        return false unless title_line?(previous_line)
        return false unless prose_line?(next_line)

        earlier_line = rebuilt[...-1]&.reverse_each&.lazy&.map { single_non_empty_line(it) }&.find { !it.to_s.empty? }
        chapter_heading_only_line?(earlier_line)
      end

      def punctuation_end?(line)
        !!(line =~ PUNCTUATION_REGEX)
      end

      def punctuation_only_line?(line)
        line.to_s.strip.match?(/\A[、。，．：；！？!?]+\z/)
      end

      def heading_line?(line)
        line.match?(HEADING_REGEX) || line.match?(SECTION_HEADING_REGEX)
      end

      def heading_start_line?(line)
        heading_line?(line) || heading_prefix_line?(line)
      end

      def chapter_heading_only_line?(line)
        line.to_s.strip.match?(CHAPTER_HEADING_ONLY_REGEX)
      end

      # 「1-2」のような見出し番号とタイトル本体が別行に割れているか
      def split_heading?(current_line, next_line)
        return false if chapter_heading_only_line?(current_line)

        heading_prefix_line?(current_line) && heading_title_line?(next_line)
      end

      def heading_prefix_line?(line)
        line.strip.match?(SECTION_HEADING_PREFIX_REGEX)
      end

      def heading_title_line?(line)
        stripped = line.strip
        return false if stripped.empty?
        return false if heading_line?(stripped)
        return false if list_line?(stripped)

        !punctuation_end?(stripped)
      end

      def title_line?(line)
        heading_title_line?(line.to_s)
      end

      def prose_line?(line)
        stripped = line.to_s.strip
        return false if stripped.empty?
        return false if heading_start_line?(stripped)
        return false if list_line?(stripped)

        true
      end

      def single_non_empty_line(block)
        lines = block.to_s.split("\n").map(&:strip).reject(&:empty?)
        return nil unless lines.length == 1

        lines.first
      end

      def first_non_empty_line(block)
        block.to_s.split("\n").map(&:strip).find { !it.empty? }
      end

      def list_line?(line)
        line.match?(LIST_MARKER_REGEX)
      end

      CJK_PAT = '[一-龯ぁ-ゖァ-ヶー々〆ヵヶ]'
      JP_PUNCT_PAT = '[、。，．：；！？!?…]'
      JP_OPEN_PAT  = '[「『（【《〈]'
      JP_CLOSE_PAT = '[」』）】》〉]'

      # 改行判定の前に、PDF 抽出特有のノイズを正規化する
      # （連続空白の縮約、句読点直前の改行除去、「第N章」と本文の間の空白挿入）
      def normalize_pdf_extracted_text(text)
        result = text.to_s
                     .gsub(/[ \t\u00A0]{2,}/, ' ')
                     .gsub(/(?<=#{CJK_PAT})\n(?=#{JP_PUNCT_PAT})/u, '')
        result = collapse_japanese_ocr_spaces(result)
        result.gsub(/(^|\n)(第[一二三四五六七八九十百千0-9]+章)(?=#{CJK_PAT})/u, '\\1\\2 ')
      end

      # 日本語文字間に紛れ込んだ半角スペースを除去する
      # （PDF のグリフ配置由来で和文の文字間に空白が挿入されることがあるため）
      def collapse_japanese_ocr_spaces(text)
        result = text.to_s
        result = result.gsub(/(?<=#{CJK_PAT}) +(?=#{CJK_PAT})/, '')
        result = result.gsub(/(?<=#{CJK_PAT}) +(?=#{JP_PUNCT_PAT})/, '')
        result = result.gsub(/(?<=#{JP_PUNCT_PAT}) +(?=#{CJK_PAT})/, '')
        result = result.gsub(/(?<=#{JP_PUNCT_PAT}) +(?=#{JP_OPEN_PAT})/, '')
        result = result.gsub(/(?<=#{JP_OPEN_PAT}) +/, '')
        result = result.gsub(/ +(?=#{JP_CLOSE_PAT})/, '')
        result = result.gsub(/(?<=#{JP_CLOSE_PAT}) +(?=#{CJK_PAT})/, '')
        result.gsub(/(?<=#{CJK_PAT}) +(?=#{JP_OPEN_PAT})/, '')
      end

      def small_kana_start?(line)
        line.match?(SMALL_KANA_START_REGEX)
      end

      def midword_break?(current_line, next_line)
        current_line.match?(MIDWORD_END_REGEX) && next_line.match?(MIDWORD_START_REGEX)
      end

      def connective_start?(line)
        trimmed = line.strip
        return false if trimmed.empty?

        prefix = CONNECTIVE_PREFIXES.find { trimmed.start_with?(it) }
        return true if prefix

        tokens = mecab_tokens(trimmed)
        tokens.first&.pos == '助詞' && tokens.first&.pos_detail1 == '接続'
      end

      # 行末が終助詞（ね・よ等）なら文末とみなす
      def sentence_ending_particle?(token)
        return false unless token&.pos == '助詞'
        return false unless token.pos_detail1.to_s.include?('終助詞')

        base = token.base.to_s.empty? ? token.surface : token.base
        ENDING_PARTICLES.include?(base)
      end

      ENDING_CONJUGATION_FORMS = %w[終止形 基本形 命令形 仮定形 体言接続].freeze

      # 行末が終止形の助動詞（です・ます等）なら文末とみなす
      def sentence_ending_auxiliary?(token)
        return false unless token&.pos == '助動詞'

        form = token.conj_form.to_s
        return false unless form.empty? || ENDING_CONJUGATION_FORMS.include?(form)

        base = token.base.to_s.empty? ? token.surface : token.base
        ENDING_AUXILIARIES.include?(base)
      end

      # 行末が格助詞・係助詞等なら文の途中とみなす（次行と結合する）
      def mid_sentence_particle?(token)
        return false unless token&.pos == '助詞'

        detail = token.pos_detail1
        %w[格助詞 並立助詞 係助詞 副助詞 接続助詞].include?(detail)
      end

      # 行末が活用途中（連用形等）の動詞・形容詞なら文の途中とみなす
      def conjugated_verb_or_adjective?(token)
        return false unless token

        pos = token.pos
        detail = token.pos_detail3

        return true if pos == '動詞' && detail != '基本形' && detail != '終止形'
        return true if pos == '形容詞' && detail != '基本形' && detail != '終止形'

        false
      end

      def particle_or_auxiliary_start?(token)
        return false unless token

        return true if token.pos == '助詞'
        return true if token.pos == '助動詞'

        false
      end

      # 行を MeCab で形態素解析して Token 配列を返す
      # 同じ行を繰り返し判定するため、外部プロセス呼び出しの結果はキャッシュする
      def mecab_tokens(line)
        key = line.strip
        return [] if key.empty?
        return @mecab_cache[key] if @mecab_cache.key?(key)

        stdout, status = Open3.capture2(mecab_command, stdin_data: key)
        return @mecab_cache[key] = [] unless status.success?

        tokens = stdout.lines.filter_map do |raw|
          stripped = raw.strip
          next if stripped.empty? || stripped == 'EOS'

          surface, features = stripped.split("\t", 2)
          parts = (features || '').split(',')
          Token.new(
            surface: surface,
            base: extract_base_form(surface, parts[6]),
            pos: parts[0],
            pos_detail1: parts[1],
            pos_detail2: parts[2],
            pos_detail3: parts[3],
            conj_type: parts[4],
            conj_form: parts[5]
          )
        end

        @mecab_cache[key] = tokens
      end

      def extract_base_form(surface, base)
        value = base.to_s.strip
        return surface if value.empty?

        value
      end
    end
  end
end
