# frozen_string_literal: true

require_relative '../masking'

module VivlioStarter
  module CLI
    module Guards
      # 「区切り線のつもりで置いた `---` が改ページになっている」原稿を検出して警告する。
      #
      # きっかけ: 2026-08-10 に判型を B5 → A4 へ変えたところ、全 26 章に 4 件の
      # 取り残しが見つかった（謝辞の 1 ブロック目の直後でページの 8 割が空白・章の最終行・
      # 項見出しの直前 2 件）。いずれも B5 でも起きていたが、版面が狭く 1 ブロックで埋まる
      # 割合が大きかったため目立たず、**A4 で版面が広がって初めて見えた**。
      # 判型を変えると紙面の前提が変わるので、変えた直後こそこの検査を走らせたい。
      #
      # 原因は記法の意味の違いにある。標準の Markdown では `---` は水平線だが、
      # **Vivlio Starter では改ページ**（`21-markdown-tutorial.md` の「水平線（改ページ）」）。
      # 素直に区切りのつもりで書くと、そこでページが終わる。
      #
      # 指摘するのは 2 つだけで、どちらも「改ページとして意味を成さないか、意図が読めない」もの:
      #   (a) 後ろに内容が無い  … 白紙が 1 枚増えるだけ。誤検知の余地がない
      #   (b) 見出しの直前      … 見出しの前でページが切れる。区切りのつもりの可能性が高い
      #
      # 逆に、**指摘しないもの**を決めておくのがこの検査の要である。
      #   - 節見出し（h2）の直前で、かつ h2 が自動改ページする設定のとき。二重改ページは
      #     PageBreakNormalizer が自動で正規化し、原稿は「気にせず書いて構いません」と
      #     `22-extentions.md` が明記している。ここで警告すると**本の説明と機能が矛盾する**
      #   - 改ページ記法が連続するとき（`---` を 2 つ重ねる）。同章が案内している
      #     「意図的に空白ページを 1 枚入れる」書き方そのもの
      #   - 後ろに本文が続くとき。区切りとしての改ページは正当な使い方
      #   - `@pagebreak` 記法。著者が改ページと知って書いた明示記法を疑うと狼少年になる
      #
      # 重大度は警告（🟡）。改ページ自体は動作しており、意図なら正しい原稿だからである。
      class StrayPageBreakCheck < BaseCheck
        # CommonMark の thematic break（`-` `*` `_` を 3 つ以上・間に空白可・行頭 3 空白まで）。
        # Vivlio ではこれが改ページになる。
        THEMATIC_BREAK = /\A {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})\z/

        # ATX 見出し（`# ` 〜 `###### `）。レベルを 1 番目のキャプチャで取る。
        HEADING = /\A {0,3}(\#{1,6})[ \t]+(.*)\z/

        # @param section_pagebreak [Boolean] h2 が CSS で自動改ページするか。
        #   既定は正典（Common）から取り、テストからは差し替える
        def initialize(section_pagebreak: Common.section_pagebreak_enabled?)
          @section_pagebreak = section_pagebreak
          super()
        end

        # @return [Array<Violation>] 警告の配列（合格なら空配列）
        def validate
          markdown_files.filter_map { |path| check_file(path) }
        end

        private

        def markdown_files
          Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).sort
        end

        # 1 ファイルを走査し、取り残しがあれば 1 件に集約した警告を返す。
        def check_file(path)
          strays = stray_breaks(File.read(path))
          return nil if strays.empty?

          warning(
            "改ページになる区切り記法が取り残されています（#{strays.size} 件）: #{path}",
            detail: strays.flat_map { stray_detail(it) } + [
              '→ 区切り線のつもりなら削除してください（Vivlio では `---` は水平線ではなく改ページです）',
              '→ 意図した改ページなら `@pagebreak` と書くと、あとから読んでも意図が分かります'
            ]
          )
        end

        # 取り残しを [行番号, 種別, 直後の見出し] の配列で返す。
        #
        # 判定は地の文の行だけを対象にする（Masking がコード領域を除くので、記法を
        # 解説するフェンスの中の `---` は拾わない。実測: 本書の `---` は全 4 件が
        # 記法解説のフェンス内で、正しく 0 件になる）。
        def stray_breaks(text)
          lines = text.lines.map(&:chomp)
          prose = prose_line_numbers(text)

          (1..lines.size).filter_map do |lineno|
            next unless prose.include?(lineno)
            next unless page_break?(lines, lineno)

            classify(lines, lineno, prose)
          end
        end

        # その行が改ページとして効く thematic break か。
        #
        # `---` は**直前が空行でないと見出しの下線**（setext heading）になり、改ページに
        # ならない。`***` / `___` にその曖昧さはないが、区別せず同じ規則で見て構わない——
        # 前が本文の行なら、いずれにせよ「区切りのつもり」の位置ではない。
        def page_break?(lines, lineno)
          return false unless lines[lineno - 1].to_s.match?(THEMATIC_BREAK)

          previous = lines[lineno - 2]
          previous.nil? || previous.strip.empty?
        end

        # 取り残しかどうかを、直後の内容から決める。該当しなければ nil。
        def classify(lines, lineno, prose)
          following = next_content_line(lines, lineno, prose)
          return [lineno, :trailing, nil] if following.nil?
          return nil if following.match?(THEMATIC_BREAK) # 意図的な空白ページ（22 章の案内）

          heading = following.match(HEADING)
          return nil unless heading
          # 自動正規化される二重改ページは原稿の問題ではない（本文が「気にせず書いてよい」と説明している）
          return nil if heading[1].size == 2 && @section_pagebreak

          [lineno, :before_heading, "#{heading[1]} #{heading[2]}"]
        end

        # 次に現れる内容行（空行とコード領域を飛ばす）。無ければ nil。
        def next_content_line(lines, lineno, prose)
          ((lineno + 1)..lines.size).each do |n|
            next unless prose.include?(n)

            line = lines[n - 1].to_s
            return line unless line.strip.empty?
          end
          nil
        end

        def prose_line_numbers(text)
          numbers = Set.new
          Masking.each_prose_line(text) { |_line, lineno| numbers << lineno }
          numbers
        end

        # 1 件ぶんの指摘行。何が起きるかまで書く（記法を見せるだけでは伝わらない）
        def stray_detail(stray)
          lineno, kind, heading = stray
          case kind
          in :trailing       then ["L#{lineno}: この後ろに内容が無いため、白紙のページが 1 枚増えるだけです"]
          in :before_heading then ["L#{lineno}: 直後の見出し「#{heading}」の前でページが切れます"]
          end
        end
      end
    end
  end
end
