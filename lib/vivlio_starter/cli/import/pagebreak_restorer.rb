# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/import/pagebreak_restorer.rb
# ================================================================
# 責務:
#   Re:VIEW の `//clearpage` を、Vivlio の `@pagebreak` へ戻す。
#
# なぜ .re を読むのか:
#   markdownbuilder の `clearpage` は `blank2()`——**空行を 2 つ置くだけ**で、
#   印を何も残さない。変換後の Markdown では、ただの段落間の空きと見分けが
#   つかない。原稿（.re）には `//clearpage` がそのまま残っているので、そちらを読む。
#
# どこへ入れるか:
#   `//clearpage` 自身には内容が無いので、**直後にくる中身**を目印にする。
#   原稿でその次に現れる素のテキストを取り、Markdown 側で同じ文字列を持つ行を
#   探して、その手前へ `@pagebreak` を置く。
#   見つけた行が囲み（`:::{.column}` など）の中にいるときは、囲みの外へ出す
#   ——中に入れると改ページが囲みの内側で起きてしまう。
# ================================================================

require_relative 'sideimage_restorer'

module VivlioStarter
  module CLI
    module Import
      # //clearpage の復元
      module PagebreakRestorer
        module_function

        CLEARPAGE = %r{\A//clearpage\s*\z}
        REVIEW_COMMENT = /\A\#@\#/

        # `@<href>{url, テキスト}` のような Re:VIEW のインライン記法
        INLINE_MARKUP = /@<[a-z]+>\{(.*?)\}/m

        # 行頭の見出し記号・カラム記号（`===` `====[column]`）
        HEADING_MARK = /\A=+(?:\[[^\]]*\])?\s*/

        # 照合のときに両側から落とす飾り
        DECORATION = /[*_`#>\s]|\A-\s/

        # 囲みの開き（`:::{.column}` など）
        FENCE_OPEN = /\A:::\{/

        def restore!(temp_dir, starter_dir)
          re_dir = SideimageRestorer.review_contents_dir(starter_dir)
          return unless Dir.exist?(re_dir)

          restored = Dir.glob(File.join(temp_dir, '*.md')).sum do |md_path|
            re_path = File.join(re_dir, "#{File.basename(md_path, '.md')}.re")
            File.exist?(re_path) ? restore_chapter!(md_path, re_path) : 0
          end

          Common.log_info("  改ページ（@pagebreak）を #{restored} 件復元しました") if restored.positive?
        end

        # 1 章ぶんを復元し、入れられた件数を返す
        def restore_chapter!(md_path, re_path)
          anchors = clearpage_anchors(File.readlines(re_path, encoding: 'utf-8'))
          return 0 if anchors.empty?

          lines = File.readlines(md_path, encoding: 'utf-8')
          points = insertion_points(lines, anchors, md_path)
          return 0 if points.empty?

          # 行番号がずれないよう後ろから入れる。直前が囲みの閉じなどで詰まっている
          # ときは空行を足す——@pagebreak は独立した 1 段落として置く記法のため
          points.sort.reverse_each do |point|
            lead = point.positive? && !lines[point - 1].strip.empty? ? "\n" : ''
            lines.insert(point, "#{lead}@pagebreak\n\n")
          end

          File.write(md_path, lines.join, encoding: 'utf-8')
          points.size
        end

        # `//clearpage` の直後にくる「素のテキスト」を出現順に返す
        def clearpage_anchors(re_lines)
          re_lines.each_index.filter_map do |i|
            next unless CLEARPAGE.match?(re_lines[i].to_s.chomp)

            ((i + 1)...re_lines.size).filter_map { plain_text(re_lines[it]) }
                                    .find { !it.empty? }
          end.compact
        end

        # Markdown 側の挿入位置を求める
        def insertion_points(lines, anchors, md_path)
          cursor = 0

          anchors.filter_map do |anchor|
            index = (cursor...lines.size).find { comparable(lines[it]).include?(comparable(anchor)) }
            next warn_unplaced(md_path, anchor) unless index

            point = hoist_above_container(lines, index)
            cursor = index + 1
            point
          end
        end

        # 囲みの中に落ちたときは、いちばん外側の囲みの開きまで持ち上げる。
        # 空行は消費しない——消費すると、入れ直した空行と重なって余分な空きになる
        def hoist_above_container(lines, index)
          point = index

          loop do
            previous = previous_content_index(lines, point)
            break unless previous && FENCE_OPEN.match?(lines[previous])

            point = previous
          end

          point
        end

        # 直前の「空行でない行」の位置。無ければ nil
        def previous_content_index(lines, from)
          index = from - 1
          index -= 1 while index >= 0 && lines[index].strip.empty?
          index.negative? ? nil : index
        end

        # Re:VIEW の 1 行から素のテキストを取り出す。命令・コメントは対象外
        def plain_text(line)
          text = line.to_s.strip
          return '' if text.empty? || text.start_with?('//') || REVIEW_COMMENT.match?(text)

          text.sub(HEADING_MARK, '')
              .gsub(INLINE_MARKUP) { Regexp.last_match(1).to_s.split(',').last.to_s.strip }
              .strip
        end

        # 飾りを落として突き合わせる（`**題名**` と `題名` を同じものと見る）
        def comparable(text) = text.to_s.gsub(DECORATION, '')

        def warn_unplaced(md_path, anchor)
          Common.log_warn(
            "  #{File.basename(md_path)}: //clearpage の位置を決められませんでした（目印: #{anchor[0, 20]}）。",
            detail: '対処: 改ページしたい位置に @pagebreak と 1 行書いてください（22 章「改ページ」）。'
          )
          nil
        end
      end
    end
  end
end
