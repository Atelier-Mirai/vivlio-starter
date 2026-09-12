# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/post_process/definition_list_converter.rb
# ================================================================
# 責務:
#   VFM が段落として出した定義リスト記法を <dl class="def-list"> へ組み直す。
#
#     用語            →  <dl class="def-list">
#     : 説明              <dt>用語</dt>
#       続きの行          <dd>説明<br>続きの行</dd>
#                       </dl>
#
# なぜ後処理なのか:
#   もとは pre_process が Markdown 段階で Kramdown に <dl> を作らせていた。
#   しかしそれだと**定義リストの中身が、以降のすべての処理から隠れる**。
#   Kramdown は VFM 固有の記法を知らないのでルビ（`{漢字|よみ}`）をそのまま
#   素通しし、索引スキャナ（ビルド Step 4）は生 HTML を「触らない領域」として
#   飛ばすため `[語|読み]` も残る——実ビルドで両方が紙面に文字として出た。
#   VFM が組み終えた HTML を受け取ってから <dl> 化すれば、ルビも索引も数式も
#   すべて効いた状態で入る（`markdown-notation-collision-spec.md` と同じ
#   「前処理で生 HTML 化すると中の記法が死ぬ」という構図）。
#
# 入力の形:
#   hardLineBreaks: true で運用しているので、VFM は定義リストのブロックを
#   1 つの <p> にまとめ、行を <br> で区切る。
#     <p>用語A<br>: 説明1。<br>続きの行。<br>用語B<br>: 説明2。</p>
# ================================================================

require_relative 'html_parser'
require_relative '../common'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # 段落として出た定義リスト記法を <dl> へ組み直す
      module DefinitionListConverter
        module_function

        # 行の区切り（VFM が hardLineBreaks で入れる <br>）
        BREAK = %r{<br\s*/?>}i

        # 定義行の頭。`: ` のあとに中身が続くもの
        DEFINITION_HEAD = /\A:[ \t]+(?=\S)/

        # 字下げした継続行の印（前処理が置く WORD JOINER。U+2060・幅ゼロ）。
        # VFM は行頭の空白を落とすので、字下げの有無はこの印でしか分からない
        CONTINUATION_MARK = "\u2060"
        CONTINUATION_HEAD = /\A#{CONTINUATION_MARK}/

        # 1 エントリ。term が nil のときは用語なしの定義（前のエントリの続き）
        Entry = Data.define(:term, :definitions)

        def convert!(html_file)
          content = File.read(html_file, encoding: 'utf-8')
          doc = HtmlParser.parse_html_document(content)
          converted = 0

          doc.css('p').each do |paragraph|
            entries = parse_entries(paragraph.inner_html)
            next if entries.nil?

            paragraph.replace(build_dl(entries))
            converted += 1
          end

          return if converted.zero?

          HtmlParser.save_html_document(html_file, doc)
          Common.log_success("#{html_file}: 定義リストを #{converted} 件組み立てました")
        end

        # 段落の中身を読み、定義リストならエントリの配列を返す。違えば nil
        #
        # @param inner_html [String] <p> の中身（VFM が組んだ HTML 片）
        # @return [Array<Entry>, nil]
        def parse_entries(inner_html)
          segments = inner_html.split(BREAK).map { it.strip }
          return nil unless definition_list?(segments)

          entries = []
          segments.each do |segment|
            if definition?(segment)
              entries.last&.definitions&.push(segment.sub(DEFINITION_HEAD, ''))
            elsif continuation?(segment)
              append_continuation(entries, segment.sub(CONTINUATION_HEAD, ''))
            else
              entries << Entry.new(term: segment, definitions: [])
            end
          end

          entries.any? { it.definitions.any? } ? entries : nil
        end

        # 「用語行の直後に定義行がある」ことを定義リストの成立条件にする。
        # `: ` で始まる行があるだけでは足りない——地の文や引用の途中に
        # コロンで始まる行が来ることがある
        def definition_list?(segments)
          segments.each_with_index.any? do |segment, index|
            definition?(segment) && index.positive? && !definition?(segments[index - 1])
          end
        end

        def definition?(segment) = DEFINITION_HEAD.match?(segment.to_s)

        def continuation?(segment) = CONTINUATION_HEAD.match?(segment.to_s)

        # 直前の定義の続き。hardLineBreaks に合わせて <br> でつなぐ
        def append_continuation(entries, segment)
          return if segment.empty?

          last = entries.last&.definitions&.last
          return unless last

          entries.last.definitions[-1] = "#{last}<br>#{segment}"
        end

        # class を付けるのは、索引・奥付が使う <dl> と衝突させないため
        def build_dl(entries)
          items = entries.flat_map do |entry|
            ["<dt>#{entry.term}</dt>", *entry.definitions.map { "<dd>#{it}</dd>" }]
          end

          %(<dl class="def-list">#{items.join}</dl>)
        end
      end
    end
  end
end
