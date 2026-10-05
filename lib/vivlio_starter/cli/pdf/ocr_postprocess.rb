# frozen_string_literal: true

require 'open3'
require 'set'
require 'yaml'

require_relative '../lint/dict_manager'

module VivlioStarter
  module PDF
    # OCR で読んだ原稿の後処理（pdf-read-ocr-postprocess-spec.md §3）。
    #
    # 当てる順は §3.3 のとおり: 和文と数字のあいだの空白 → 形の似た字 → 英字の語 → 括弧 → 補正表。
    # 形の似た字の判定は前後の空白を詰めてからのほうが単純になり、補正表は利用者の上書きなので
    # 最後に当てる。英字の語（OcrLatinWords）だけはコードの囲みの中にもかけ、ほかは囲みの外だけにかける。
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
      # @param vocabulary [Set<String>, nil] 英字の語の辞書（小文字）。nil なら OcrLatinWords.vocabulary を読む
      def apply(markdown, corrections_path: OcrCorrections.default_path, mecab: 'mecab', vocabulary: nil)
        rules = OcrCorrections.load_rules(corrections_path)
        text = outside_code(markdown) { fix_confusables(collapse_digit_spacing(it), mecab) }
        text = OcrLatinWords.fix_markdown(text, vocabulary || OcrLatinWords.vocabulary)
        outside_code(text) { OcrCorrections.correct(normalize_brackets(it), rules) }
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

    # OCR が取り違えた英字の語を、`vs lint` のスペルチェックの辞書で直す
    # （pdf-read-ocr-improvement-notes.md §4.3）。
    #
    # 語を `_` と大文字の境目で部品に分け、辞書に無い部品だけ、OCR が取り違えやすい字を入れ替える。
    # 辞書に当たる形が 1 つだけのときに直す（`Ftoat` → `Float`、`threshotd_frequency` →
    # `threshold_frequency`）。97 章のスキャンで英字の語が 185 → 205（原稿に 250）、誤りの無い原稿
    # 29 章の 1,575 語にかけて書き換わるのは 1 語。コードの識別子こそ直したいので、囲みの中にもかける
    module OcrLatinWords
      # OCR が取り違えやすい英字の組。左の字を右の字に戻す候補にする
      SWAPS = {
        't' => %w[l i f], 'l' => %w[t i], 'i' => %w[l t], 'f' => %w[t], 'c' => %w[e], 'e' => %w[c],
        'h' => %w[b], 'b' => %w[h], 'n' => %w[u], 'u' => %w[n], 'rn' => %w[m], 'm' => %w[rn], 'H' => %w[R]
      }.freeze
      # この長さに満たない部品は直さない（`stp` → `sip` のような 3 字の語の取り違えを防ぐ）
      MIN_PART = 4
      # t を l・i に戻すのは、t がこの数までの部品だけ。Tesseract は細い字体で l・i をほとんど t と読み、
      # `velocity` が `vetoctty` になるので、1 か所の入れ替えでは足りない
      MAX_T = 5
      # 英語の単語表。lint の辞書に無い一般の語（trajectory・deflection・brownian）を補う。無い環境では使わない
      SYSTEM_WORDS = '/usr/share/dict/words'
      # 書き換えない範囲: 画像の参照（ファイル名）と HTML のコメント
      PROTECTED = /(!\[[^\]]*\]\([^)]*\)|<!--.*?-->)/m
      WORD = /[A-Za-z_][A-Za-z0-9_]{2,}/

      module_function

      # `vs lint` の辞書（プロジェクトの config/spellcheck_dictionaries・用語集・除外リスト）と単語表
      # @return [Set<String>] 小文字の語
      def vocabulary
        words = CLI::Lint::DictManager.new.build_word_map(nil).keys.to_set
        return words unless File.file?(SYSTEM_WORDS)

        File.foreach(SYSTEM_WORDS, chomp: true) { words << it.downcase }
        words
      end

      def fix_markdown(markdown, vocabulary)
        # 区切りを括弧で取るので、奇数番目の部品が保護する範囲になる
        markdown.split(PROTECTED).each_with_index.map { |part, index| index.odd? ? part : fix(part, vocabulary) }.join
      end

      def fix(text, vocabulary) = text.gsub(WORD) { fix_word(it, vocabulary) }

      def fix_word(word, vocabulary)
        word.split(/(_|(?<=[a-z])(?=[A-Z]))/).map do |part|
          next part if part.size < MIN_PART || part.match?(/\d/) || vocabulary.include?(part.downcase)

          hits = single_swaps(part).select { vocabulary.include?(it.downcase) }
          hits = t_swaps(part).select { vocabulary.include?(it.downcase) } if hits.empty?
          hits.uniq.size == 1 ? hits.first : part
        end.join
      end

      # 1 か所だけ入れ替えた形
      def single_swaps(part)
        SWAPS.flat_map do |from, targets|
          positions = (0..(part.size - from.size)).select { part[it, from.size] == from }
          positions.flat_map { |at| targets.map { "#{part[0...at]}#{it}#{part[(at + from.size)..]}" } }
        end.uniq
      end

      # t を l・i に戻す入れ替えを、複数か所まで組み合わせた形
      def t_swaps(part)
        positions = (0...part.size).select { part[it] == 't' }
        return [] if positions.empty? || positions.size > MAX_T

        %w[t l i].repeated_permutation(positions.size).filter_map do |choice|
          candidate = part.dup
          positions.zip(choice).each { |at, char| candidate[at] = char }
          candidate unless candidate == part
        end
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
