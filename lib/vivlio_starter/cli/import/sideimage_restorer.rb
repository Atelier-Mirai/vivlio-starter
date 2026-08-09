# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/import/sideimage_restorer.rb
# ================================================================
# 責務:
#   Re:VIEW Starter の `//sideimage` を Vivlio の `:::{.sideimage}` へ戻す。
#
# なぜ .re を読むのか:
#   Re:VIEW の markdownbuilder は `//sideimage` を
#     `<img src="…">` ＋ 空行 ＋ 本文
#   へ平坦化し、**囲みの終わりを示す印を残さない**（`_render_sideimage`）。
#   変換後の Markdown だけを見ても「どこまでが画像の脇に置く本文か」は決められない。
#   原稿（.re）には囲みがそのまま残っているので、そちらを読んで並びを突き合わせる
#   ——推測ではなく、原文の構造をそのまま移す。
#
# 対応づけ:
#   .re と .md は basename が一致する（00-preface.re ↔ 00-preface.md）ので、
#   章ごとに「.re に現れた順」と「.md に現れた順」で突き合わせる。
#
# 依存:
#   - YamlProcessor: 判型プリセットの対応表
#   - ImageFilenameSanitizer: 取り込み時と同じファイル名の正規化
#   - Units / Common::PAGE_SIZES: mm → % の換算
# ================================================================

require 'yaml'

require_relative '../units'
require_relative '../image_filename_sanitizer'
require_relative 'yaml_processor'

module VivlioStarter
  module CLI
    module Import
      # //sideimage の復元
      module SideimageRestorer
        module_function

        # `//sideimage[画像][幅][オプション]{`
        SIDEIMAGE_OPEN = %r{\A//sideimage\[([^\]]*)\]\[([^\]]*)\]\[([^\]]*)\]\{\s*\z}

        # Re:VIEW のブロック終端 `//}`
        BLOCK_CLOSE = %r{\A//\}\s*\z}

        # 画像の脇に置く本文を数えるとき、ここに来たら必ず打ち切る
        # （見出し・別の囲み・水平線・次の画像）
        STOP_LINE = /\A(?:\#{1,6}\s|:::|---\s*\z|!\[)/

        # 判型が読めないときの版面幅（mm）。B5 標準相当
        DEFAULT_TEXT_WIDTH_MM = 137.0

        # 画像列の比率の下限・上限。極端な指定で本文の列が潰れるのを防ぐ
        WIDTH_PERCENT_RANGE = (10..60).freeze

        PAGE_PRESETS_FILE = 'config/page_presets.yml'

        # temp/ の Markdown に対して sideimage の囲みを復元する
        #
        # @param temp_dir [String] 変換済み Markdown の置き場
        # @param starter_dir [String] Re:VIEW Starter プロジェクトのディレクトリ
        # @return [void]
        def restore!(temp_dir, starter_dir)
          re_dir = review_contents_dir(starter_dir)
          return unless Dir.exist?(re_dir)

          text_mm = text_area_width_mm(starter_dir)

          restored = Dir.glob(File.join(temp_dir, '*.md')).sum do |md_path|
            re_path = File.join(re_dir, "#{File.basename(md_path, '.md')}.re")
            File.exist?(re_path) ? restore_chapter!(md_path, re_path, text_mm) : 0
          end

          Common.log_info("  sideimage の囲みを #{restored} 件復元しました") if restored.positive?
        end

        # 1 章ぶんを復元し、復元できた件数を返す
        def restore_chapter!(md_path, re_path, text_mm)
          directives = parse_directives(File.readlines(re_path, encoding: 'utf-8'))
          return 0 if directives.empty?

          lines = File.readlines(md_path, encoding: 'utf-8')
          spans = locate_spans(lines, directives, md_path)
          return 0 if spans.empty?

          # 行番号がずれないよう後ろから書き換える
          spans.reverse_each do |image_idx, last_idx, directive|
            lines[last_idx] = "#{lines[last_idx].chomp}\n:::\n"
            lines[image_idx] = image_line_with_width(lines[image_idx], directive, text_mm)
            lines.insert(image_idx, ":::{.#{directive[:klass]}}\n")
          end

          File.write(md_path, lines.join, encoding: 'utf-8')
          spans.size
        end

        # .re の並び順に、Markdown 側の [画像行, 本文の最終行, 指示] を求める
        def locate_spans(lines, directives, md_path)
          cursor = 0

          directives.filter_map do |directive|
            image_idx = find_image_line(lines, directive[:image], cursor)
            next warn_unplaced(md_path, directive) unless image_idx

            last_idx = body_end(lines, image_idx, directive[:blocks])
            cursor = last_idx + 1
            [image_idx, last_idx, directive]
          end
        end

        # .re から sideimage の指示を出現順に取り出す
        def parse_directives(re_lines)
          directives = []
          i = 0

          while i < re_lines.size
            match = SIDEIMAGE_OPEN.match(re_lines[i].to_s.chomp)
            if match
              body = []
              i += 1
              while i < re_lines.size && !BLOCK_CLOSE.match?(re_lines[i].to_s.chomp)
                body << re_lines[i].to_s.chomp
                i += 1
              end
              directives << build_directive(match, body)
            end
            i += 1
          end

          directives
        end

        def build_directive(match, body)
          {
            image: ImageFilenameSanitizer.sanitize(match[1].to_s.strip),
            width_mm: Units.length_to_mm(match[2].to_s.strip),
            klass: match[3].to_s.include?('side=R') ? 'sideimage-right' : 'sideimage',
            blocks: text_block_count(body)
          }
        end

        # 本文のブロック数。`//blankline` のように「Markdown では空行にしかならない」
        # 命令だけのブロックは数えない——数えると本文を 1 つ多く巻き込む。
        def text_block_count(body)
          body.join("\n").split(/\n[ \t]*\n/)
              .count { |block| block.lines.any? { text_line?(it) } }
        end

        def text_line?(line)
          stripped = line.strip
          !stripped.empty? && !stripped.start_with?('//')
        end

        # 画像行を探す。取り込み時と同じ正規化を通した名前で照合する
        def find_image_line(lines, image, from)
          needle = "](#{image}.webp)"
          (from...lines.size).find { lines[it].include?(needle) && lines[it].lstrip.start_with?('![') }
        end

        # 画像行のうしろから、原稿にあったぶんの本文ブロックを数えて終端の行を返す
        def body_end(lines, image_idx, blocks)
          i = image_idx + 1
          last = image_idx

          blocks.times do
            i += 1 while i < lines.size && lines[i].strip.empty?
            break if i >= lines.size || STOP_LINE.match?(lines[i])

            i += 1 while i < lines.size && !lines[i].strip.empty?
            last = i - 1
          end

          last
        end

        # 画像行へ `{width=NN%}` を添える。Vivlio ではこの値がそのまま画像列の比率になる
        def image_line_with_width(line, directive, text_mm)
          percent = width_percent(directive[:width_mm], text_mm)
          return line unless percent

          "#{line.chomp}{width=#{percent}%}\n"
        end

        def width_percent(width_mm, text_mm)
          return nil unless width_mm&.positive? && text_mm.positive?

          ((width_mm / text_mm) * 100).round.clamp(WIDTH_PERCENT_RANGE.begin, WIDTH_PERCENT_RANGE.end)
        end

        # 版面幅（mm）＝ 紙幅 − ノド − 小口。Re:VIEW の mm 指定を比率へ直す基準
        def text_area_width_mm(starter_dir)
          preset = target_page_preset(starter_dir)
          return DEFAULT_TEXT_WIDTH_MM unless preset

          width = Units.length_to_mm(Common::PAGE_SIZES.dig(preset['size'].to_s.upcase, :width))
          inner = Units.length_to_mm(preset['margin_inner'])
          outer = Units.length_to_mm(preset['margin_outer'])
          return DEFAULT_TEXT_WIDTH_MM unless width&.positive? && inner && outer

          [width - inner - outer, 1.0].max
        end

        # 取り込み先で使う判型プリセットの中身
        def target_page_preset(starter_dir)
          starter_config = File.join(starter_dir, 'config-starter.yml')
          return nil unless File.exist?(starter_config) && File.exist?(PAGE_PRESETS_FILE)

          pagesize = YAML.safe_load_file(starter_config, permitted_classes: [Symbol]).dig('starter', 'pagesize')
          name = YamlProcessor::PAGE_PRESETS[pagesize.to_s.strip.upcase]
          return nil unless name

          # プリセットは YAML アンカー（`<<: *b5_std`）で共通部を引くため aliases が要る
          YAML.safe_load_file(PAGE_PRESETS_FILE, aliases: true)[name]
        end

        # Re:VIEW の原稿ディレクトリ（config.yml の contentdir。既定は contents）
        def review_contents_dir(starter_dir)
          config = File.join(starter_dir, 'config.yml')
          dir = (YAML.safe_load_file(config, permitted_classes: [Symbol])['contentdir'] if File.exist?(config))
          File.join(starter_dir, dir.to_s.strip.empty? ? 'contents' : dir.to_s.strip)
        end

        # 置き場所が決まらなかった指示は、著者が手で直せるように名指しで知らせる
        def warn_unplaced(md_path, directive)
          Common.log_warn(
            "  #{File.basename(md_path)}: sideimage の画像 #{directive[:image]} が見つからず、囲みを復元できませんでした。",
            detail: "対処: 該当箇所を :::{.#{directive[:klass]}} … ::: で囲んでください" \
                    '（22 章「サイドイメージ」）。'
          )
          nil
        end
      end
    end
  end
end
