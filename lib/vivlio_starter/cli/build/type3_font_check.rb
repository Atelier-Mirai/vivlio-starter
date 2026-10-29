# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/type3_font_check.rb
# ================================================================
# 責務:
#   仕上がった PDF に Type 3 書体が混ざっていないかを調べ、混ざったページと字を 🟡 で知らせる
#   （改善案 #124 の案 B）。
#
# なぜ混ざるのか:
#   本の書体に無い字（≒・ⁿ・∛・⌃・絵文字など）は、Chromium が OS の書体（ヒラギノ・
#   Apple Color Emoji など）に切り替えて描き、その書体を Type 3 で埋め込む。紙面には字が
#   ちゃんと出るので見ただけでは気づけず、印刷所の入稿で初めて指摘される。
#   同梱の Noto Sans JP・Serif JP（Google Fonts 版）と HackGen には、こうした記号が無いものが多い。
#
# 調べ方:
#   1. qpdf の JSON で、ページの書体（Form XObject の中も）から /Subtype /Type3 を拾う。
#      ページごとに pdffonts を呼ぶと 900 ページの本で遅い（JSON なら一度で 3 秒ほど）。
#   2. Type 3 のあったページだけを qpdf で抜き出し、pdf-reader で読んで、その書体で描かれた字を取り出す。
#      仕上がった PDF を pdf-reader で開くと、大きなオブジェクトストリームを読むだけで 900 ページの本で
#      35 秒かかる。抜き出した小さな PDF なら一瞬で開ける。
#      書体は、字を描く時点の書体で見分ける（Q で元の書体に戻るのは pdf-reader の PageState が扱う）。
#   3. PDF のしおりから、そのページの章・節の題を引いて、場所の手がかりに添える。字と同じページで
#      始まる節は、飛び先の高さが字より上のときだけ使う（字の後で始まる節の題を出さない）。
#
# 組めなかった数式も見つかる:
#   MathJax は組めない式（`^{a}^{b}` の上付きの重なりなど）を、元の TeX を文字にして描く。その字は
#   汎用の書体で描かれて Type 3 になり、紙面では式の代わりに帯が出る。TeX に見える字の並びは、
#   書体に無い字ではなく「数式が組めていない」として知らせる（spiral-ruby の合本で 3 か所見つかった）。
#
#   読むだけなので QpdfJson.read は使わない（あれは更新のためにオブジェクトストリームを外し、
#   PDF を書き直す）。JSON にはストリームの中のオブジェクトも並ぶので、外さなくても引ける。
#
# 全章ビルドだけで調べる:
#   単章ビルドは絵文字を画像にしないなど組み方が違い、Type 3 の有無が当てにならない
#   （SINGLE_MODE_SKIP の techbook post-process）。ステップは :whole_book なので単章では走らない。
# ================================================================

require 'json'
require 'open3'
require 'pdf/reader'
require 'tmpdir'
require_relative '../pre_process/math_transformer'
require_relative '../pre_process/glyph_coverage_check'

module VivlioStarter
  module CLI
    module Build
      module Type3FontCheck
        # Type 3 で描かれた字のあるページ。text はその書体で描かれた字を描いた順に並べたもの、
        # heading はしおりから引いたそのページの章・節の題（無ければ nil）
        Finding = Data.define(:page, :text, :heading) do
          # 空白を除いた、重ならない字
          def chars = text.each_grapheme_cluster.reject { it.strip.empty? }.uniq

          # MathJax が組めなかった式の TeX か（`\pi`・`^{…}`・`_{…}`）
          def math_error? = text.match?(MATH_SOURCE)
        end

        # 組めなかった式として描かれた TeX の手がかり
        MATH_SOURCE = /\\[A-Za-z]+|[\^_]\{/

        # 知らせに載せる、組めなかった式の長さの上限
        MATH_EXCERPT_LENGTH = 60

        # 知らせるページの上限。絵文字を本文に多用した本でも、警告が画面を埋めないように
        MAX_LISTED_PAGES = 20

        module_function

        # 仕上がった PDF を調べ、Type 3 の字があれば 🟡 で知らせる。PDF が無ければ何もしない。
        #
        # @param pdf_path [String]
        # @return [Array<Finding>]
        def check!(pdf_path)
          return [] unless File.exist?(pdf_path)

          findings = scan(pdf_path)
          # 組めなかった式は、前処理が原稿の行で知らせている（MarkdownPreprocessor#warn_math_errors）。
          # ここで重ねて言うのは、前処理で式を SVG にできなかった（mathjax-full が無い）ときだけ
          listed = PreProcessCommands::MathTransformer.available? ? findings.reject(&:math_error?) : findings
          listed = without_reported_chars(listed)
          warn_findings(listed, File.basename(pdf_path)) unless listed.empty?
          findings
        end

        # 本の書体に無い字は、前処理が原稿の行で知らせている（GlyphCoverageCheck）。その字は外し、
        # 残りの字が無くなったページは知らせない。前処理で見つからなかった字（書体の切り替えの
        # 見込み違い・CSS で足した字など）だけが、ここで出る
        def without_reported_chars(findings)
          known = PreProcessCommands::GlyphCoverageCheck.reported
          return findings if known.empty?

          findings.filter_map do |finding|
            next finding if finding.math_error?

            rest = finding.text.each_grapheme_cluster.reject { known.include?(it.gsub(PreProcessCommands::GlyphCoverageCheck::IGNORED, '')) }
            finding.with(text: rest.join) unless rest.join.strip.empty?
          end
        end

        # @param pdf_path [String]
        # @return [Array<Finding>] ページ順
        def scan(pdf_path)
          document = read_structure(pdf_path)
          return [] unless document

          pages = type3_pages(document)
          return [] if pages.empty?

          headings = outline_headings(document['outlines'] || [])
          type3_texts(pdf_path, pages).zip(pages).map do |(text, top), page|
            Finding.new(page:, text:, heading: heading_at(headings, page, top))
          end
        end

        # 字のある位置より前で始まる、いちばん後の章・節の題。同じページの節は、飛び先の高さ（top）が
        # 字の高さ（PDF の座標なので上ほど大きい）以上のものだけ。高さの分からない節は前とみなす
        def heading_at(headings, page, glyph_top)
          headings.reverse_each.find do |start, top, _title|
            start < page || (start == page && (top.nil? || glyph_top.nil? || top >= glyph_top))
          end&.last
        end

        # ページを抜き出した PDF を読み、ページごとに Type 3 の書体で描かれた字と、その最も高い位置を返す
        #
        # @return [Array<Array(String, Float)>] pages と同じ順。高さは取れなければ nil
        def type3_texts(pdf_path, pages)
          Dir.mktmpdir('vs-type3') do |dir|
            extracted = File.join(dir, 'pages.pdf')
            unless system('qpdf', '--empty', '--pages', pdf_path, pages.join(','), '--', extracted, out: File::NULL, err: File::NULL)
              Common.log_warn("[pdf] Type 3 書体で描かれた字を取り出せませんでした（qpdf が失敗）: #{File.basename(pdf_path)}")
              return pages.map { ['', nil] }
            end

            ::PDF::Reader.new(extracted).pages.map do |page|
              receiver = Type3TextReceiver.new
              page.walk(receiver)
              [receiver.text, receiver.top]
            end
          end
        end

        # qpdf の JSON（構造・ページ・しおり）。ストリームの中身は読まないので大きな PDF でも軽い
        def read_structure(pdf_path)
          out, status = Open3.capture2('qpdf', pdf_path, '--json=2', '--json-key=qpdf', '--json-key=pages',
                                       '--json-key=outlines', '--json-stream-data=none', err: File::NULL)
          return JSON.parse(out) if status.success?

          Common.log_warn("[pdf] Type 3 書体の有無を調べられませんでした（qpdf が失敗）: #{File.basename(pdf_path)}")
          nil
        rescue StandardError => e
          Common.log_warn("[pdf] Type 3 書体の有無を調べられませんでした: #{e.message}")
          nil
        end

        # @return [Array<Integer>] Type 3 書体を使うページ（1 から数える）
        def type3_pages(document)
          _header, objects = document['qpdf']
          resolve = ->(value) { value.is_a?(String) && value.end_with?(' R') ? dictionary(objects["obj:#{value}"]) : value }
          type3 = objects.filter_map { |key, object| key.delete_prefix('obj:') if dictionary(object)&.dig('/Subtype') == '/Type3' }.to_set
          return [] if type3.empty?

          document['pages'].each_with_index.filter_map do |page, index|
            index + 1 if uses_type3?(page_resources(resolve.(page['object']), resolve), resolve, type3, {})
          end
        end

        # 書体の辞書に Type 3 があるか。Form XObject（図など）の中へも降りる
        def uses_type3?(resources, resolve, type3, visited)
          resources = resolve.(resources)
          return false unless resources.is_a?(Hash)
          return true if (resolve.(resources['/Font']) || {}).each_value.any? { type3.include?(it) }

          (resolve.(resources['/XObject']) || {}).each_value.any? do |ref|
            next false if visited[ref]

            visited[ref] = true
            xobject = resolve.(ref)
            xobject.is_a?(Hash) && xobject['/Subtype'] == '/Form' && uses_type3?(xobject['/Resources'], resolve, type3, visited)
          end
        end

        # ページの /Resources。ページに無ければ親（/Pages）から受け継ぐ
        def page_resources(page, resolve)
          page = resolve.(page['/Parent']) while page.is_a?(Hash) && !page.key?('/Resources') && page['/Parent']
          page.is_a?(Hash) ? page['/Resources'] : nil
        end

        # qpdf の JSON のオブジェクトの辞書（ストリームなら辞書の部分）。配列・数などの値は nil
        def dictionary(object)
          value = object && (object['value'] || object.dig('stream', 'dict'))
          value if value.is_a?(Hash)
        end

        # しおりの 2 段目（章と節）までを [開始ページ, 飛び先の高さ, 題] の並びにする。
        # 高さは飛び先が `/XYZ 左 上 倍率` のときの「上」で、章扉のような `/Fit` では nil
        def outline_headings(outlines)
          outlines.flat_map { [it, *it['kids']] }.filter_map do |item|
            next unless item['destpageposfrom1']

            dest = item['dest']
            top = dest[3] if dest.is_a?(Array) && dest[1] == '/XYZ' && dest[3].is_a?(Numeric)
            [item['destpageposfrom1'], top, item['title'].to_s.strip]
          end
        end

        def warn_findings(findings, pdf_name)
          lines = findings.first(MAX_LISTED_PAGES).map { finding_line(it) }
          lines << "ほか #{findings.size - MAX_LISTED_PAGES} ページ" if findings.size > MAX_LISTED_PAGES
          Common.log_warn("#{findings.size} ページで、字が本の書体でなく OS の書体（Type 3）で組まれています。" \
                          "印刷所の入稿で断られることがあります: #{pdf_name}",
                          detail: lines.join("\n"))
        end

        # 「43 ページ目（課題7　…）: ⌃ → Control・…のように言葉で書く」。直し方が同じ字はまとめる。
        # 組めなかった式は、式の TeX をそのまま見せる（字を一つずつ並べても式だと分からない）
        def finding_line(finding)
          # ページは PDF の通し番号（ノンブルではない）。PDF を開いてそのまま飛べるように
          place = finding.heading ? "#{finding.page} ページ目（#{finding.heading}）" : "#{finding.page} ページ目"
          if finding.math_error?
            excerpt = finding.text.strip.then { it.length > MATH_EXCERPT_LENGTH ? "#{it[0, MATH_EXCERPT_LENGTH]}…" : it }
            return "#{place}: 数式が組めていません: #{excerpt} → 式の書き方を直す（^ や _ の重なりなど）"
          end

          fixes = finding.chars.group_by { advice_for(it) }.map { |advice, chars| "#{chars.join(' ')} → #{advice}" }
          "#{place}: #{fixes.join(' ／ ')}"
        end

        # 字ごとの直し方は、前処理の確かめ（GlyphCoverageCheck）と共用
        def advice_for(char) = PreProcessCommands::GlyphCoverageCheck.advice_for(char)

        # Type 3 の書体で描かれた字を集める。書体は描く時点の書体（PageState が q/Q で出し入れする）で見る
        class Type3TextReceiver < ::PDF::Reader::PageTextReceiver
          # @return [String] Type 3 の書体で描いた字を、描いた順につなげたもの
          attr_reader :text

          # @return [Float, nil] Type 3 の字を描き始めた位置のうち、いちばん高いもの（PDF の座標・pt）
          attr_reader :top

          def initialize
            super
            @text = +''
          end

          # 「'」と「"」の命令は中で show_text を呼ぶので、包むのはこの 2 つだけでよい
          def show_text(string)
            record_chars([string])
            super
          end

          def show_text_with_positioning(params)
            record_chars(params.grep(String))
            super
          end

          private

          def record_chars(strings)
            font = @state.current_font
            return unless font&.subtype == :Type3

            strings.each { @text << font.to_utf8(it) }
            y = @state.trm_transform_point(::PDF::Reader::Point.new(0, 0)).y
            @top = [@top, y].compact.max
          end
        end
      end
    end
  end
end
