# frozen_string_literal: true

require 'open3'
require 'yaml'

module VivlioStarter
  module PDF
    # OCR で読んだ原稿の後処理（pdf-read-ocr-postprocess-spec.md §3）。
    #
    # 当てる順は §3.3 のとおり: 和文と数字のあいだの空白 → 形の似た字 → 括弧 → 補正表。
    # 形の似た字の判定は前後の空白を詰めてからのほうが単純になり、補正表は利用者の上書きなので
    # 最後に当てる。コードの囲みの中には何もしない。
    module OcrPostprocess
      # 和文の文字（約物を含む）
      WIDE = /[\p{Han}\p{Hiragana}\p{Katakana}ー々〆、。，．・「」『』（）！？：；…—―〜]/

      # OCR が取り違えやすい形の似た字の組（§3.2）。左を右に直す候補にする。
      # 字体によって出方が大きく違うので、組は表で持って増やせるようにする
      CONFUSABLES = {
        '6' => 'も', 'カ' => '力', '力' => 'カ', 'ロ' => '口', '口' => 'ロ', 'ヘ' => 'へ', 'へ' => 'ヘ',
        '一' => 'ー', 'ー' => '一', '−' => 'ー', '工' => 'エ', 'エ' => '工', '夕' => 'タ', 'タ' => '夕',
        '卜' => 'ト', 'ト' => '卜', '二' => 'ニ', 'ニ' => '二', '八' => 'ハ', 'ハ' => '八'
      }.freeze

      # 入れ替えた形の MeCab のコストが、元の形よりこれ以上低いときだけ直す。
      # 実例 14 組で最も差の小さい「ニュートン力学／ニュートンカ学」でも 3,589 あった
      COST_MARGIN = 2000

      # MeCab に渡す前後の字数。文の切れ目（。！？）でも止める
      WINDOW = 10

      module_function

      # @param markdown [String]
      # @param corrections_path [String] 補正表（config/ocr_corrections.yml）のパス
      # @param mecab [String] MeCab のコマンド。無ければ形の似た字の補正だけを飛ばす
      # @return [String]
      def apply(markdown, corrections_path: OcrCorrections.default_path, mecab: 'mecab')
        rules = OcrCorrections.load_rules(corrections_path)
        outside_code(markdown) do |text|
          text = collapse_digit_spacing(text)
          text = fix_confusables(text, mecab)
          text = normalize_brackets(text)
          OcrCorrections.correct(text, rules)
        end
      end

      # コードの囲みの外だけをブロックに渡して書き換える
      def outside_code(markdown)
        markdown.split(/^(```.*?^```[^\n]*\n?)/m).map { it.start_with?('```') ? it : yield(it) }.join
      end

      # 数字と和文のあいだの空白を詰める（「1879 年」→「1879年」）。英字の語と和文のあいだは
      # 本ごとに方針が違うので詰めず、`vs lint` に任せる（論点 2）。数字どうしの空白は触らない
      def collapse_digit_spacing(text)
        text.gsub(/(?<=\d) +(?=#{WIDE})/, '').gsub(/(?<=#{WIDE}) +(?=\d)/, '')
      end

      # 和文を含む半角括弧は全角にし、全角括弧の外側に残った空白も詰める（「塊 （量子） として」）
      def normalize_brackets(text)
        text.gsub(/\(([^()\n]*\p{Han}[^()\n]*|[^()\n]*\p{Hiragana}[^()\n]*|[^()\n]*\p{Katakana}[^()\n]*)\)/) { "（#{$1.strip}）" }
            .gsub(/(?<=#{WIDE}) +(?=（)/, '').gsub(/(?<=）) +(?=#{WIDE})/, '')
      end

      # 形の似た字を、まわりと字の種類が違う箇所だけ候補にし、MeCab のコストで確かめて直す。
      # 文字の種類だけで決めると「ニュートン力学」「イタリアへ」のような正しい文を壊す（§3.2）
      def fix_confusables(text, mecab)
        candidates = confusable_candidates(text)
        return text if candidates.empty?

        costs = mecab_costs(candidates.flat_map { [it[:original], it[:variant]] }, mecab)
        return text unless costs

        fixed = text.dup
        candidates.each_with_index do |candidate, index|
          original, variant = costs.values_at(index * 2, (index * 2) + 1)
          fixed[candidate[:position]] = CONFUSABLES[candidate[:char]] if original && variant && variant < original - COST_MARGIN
        end
        fixed
      end

      # 候補は、組の字が前後どちらとも違う種類の文字に挟まれた 1 字（「協カ」「ブ口グ」「コ一ド」）。
      # 片方が同じ種類なら語の一部とみなして触らない（「父ヘルマン」のヘは片仮名の語の頭）。
      # 「6」は、数字に挟まれず、直前が和文のときだけ（「向けて6、」）
      def confusable_candidates(text)
        chars = text.chars
        chars.each_with_index.filter_map do |char, position|
          next unless CONFUSABLES.key?(char)

          before = position.positive? ? chars[position - 1] : nil
          after = chars[position + 1]
          next unless candidate?(char, before, after)

          window = window_around(chars, position)
          variant = window[:text].dup
          variant[window[:offset]] = CONFUSABLES[char]
          { position:, char:, original: window[:text], variant: }
        end
      end

      def candidate?(char, before, after)
        if char == '6'
          return before.to_s.match?(WIDE) && !before.to_s.match?(/\d/) && !after.to_s.match?(/[\d.,]/)
        end

        kind = script(char)
        neighbors = [before, after].filter_map { script(it) if it }
        !neighbors.empty? && neighbors.none?(kind)
      end

      # 字の種類。長音は片仮名、「一」は漢字として扱う
      def script(char)
        case char
        when /\p{Han}/ then :han
        when /\p{Hiragana}/ then :hiragana
        when /[\p{Katakana}ー]/ then :katakana
        end
      end

      # 候補の字の前後 WINDOW 字。文の切れ目と改行で止める
      def window_around(chars, position)
        start = position
        start -= 1 while start.positive? && position - start < WINDOW && !chars[start - 1].match?(/[。！？\n]/)
        stop = position
        stop += 1 while stop < chars.size - 1 && stop - position < WINDOW && !chars[stop].match?(/[。！？\n]/)
        { text: chars[start..stop].join, offset: position - start }
      end

      # 各行を MeCab にかけ、文全体のコスト（最後の語までの累積コスト）を返す。
      # MeCab が無い・失敗したときは nil（補正を飛ばす。改行の補正と同じ扱い）
      def mecab_costs(lines, mecab)
        input = lines.map { it.tr("\n", ' ') }.join("\n")
        stdout, status = Open3.capture2(mecab, '-F', '%pc ', '-E', "\n", stdin_data: "#{input}\n")
        return nil unless status.success?

        costs = stdout.lines.map { it.split.last&.to_i }
        costs.size >= lines.size ? costs.first(lines.size) : nil
      rescue Errno::ENOENT
        nil
      end
    end

    # OCR の誤認識を config/ocr_corrections.yml の表で直す。
    #
    # **当てるのは OCR したページから組んだ原稿だけ**で、著者が自分で書いた原稿には触れない。
    # 走査の誤りと表記の方針は別物なので、校正辞書（prh）とは表を分けている。コードの囲みの中は直さない
    module OcrCorrections
      # 補正表の置き場。プロジェクトごとに育てるものなので gem には持たせない
      FILE = File.join('config', 'ocr_corrections.yml')

      module_function

      def default_path = File.join(Dir.pwd, FILE)

      # @param markdown [String]
      # @param path [String] 補正表のパス
      # @return [String]
      def apply(markdown, path: default_path)
        rules = load_rules(path)
        return markdown if rules.empty?

        OcrPostprocess.outside_code(markdown) { correct(it, rules) }
      end

      def correct(text, rules) = rules.reduce(text) { |memo, (matcher, expected)| memo.gsub(matcher, expected) }

      # 表が無いプロジェクト（1.0 より前の雛形）や読めない表では、直さずに素通りさせる
      def load_rules(path)
        return [] unless File.file?(path)

        data = YAML.safe_load_file(path, aliases: true) || {}
        Array(data['rules']).flat_map do |rule|
          expected = rule['expected'].to_s
          next [] if expected.empty?

          Array(rule['patterns']).filter_map { (matcher = compile(it)) && [matcher, expected] }
        end
      rescue StandardError
        []
      end

      # 「/…/」で囲んだものは正規表現、それ以外は文字どおりに探す
      def compile(pattern)
        value = pattern.to_s.strip
        return nil if value.empty?

        value.match?(%r{\A/.+/\z}) ? Regexp.new(value[1...-1]) : Regexp.new(Regexp.escape(value))
      rescue RegexpError
        nil
      end
    end
  end
end
