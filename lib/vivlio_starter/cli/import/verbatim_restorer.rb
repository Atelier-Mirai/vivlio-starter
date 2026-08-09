# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/import/verbatim_restorer.rb
# ================================================================
# 責務:
#   Re:VIEW の `//output` / `//cmd` / `//terminal` を、Vivlio の
#   `:::{.output}` / `:::{.terminal}` へ戻す。
#
# なぜ .re を読むのか:
#   Re:VIEW の markdownbuilder（`_render_codeblock`）は `//list` も `//output` も
#   同じ ```lang フェンスへ落とし、**ブロックの種別を残さない**。変換後の Markdown を
#   見ても、それがソースコードなのか実行結果なのか区別できない。
#   区別できないと実行結果に行番号が付く——`.output` / `.terminal` の中の逐語ブロックは
#   行番号を付けない決まり（22 章）なので、素のコードフェンスのままだと誤って付く。
#
# 対応づけ:
#   `_render_codeblock` は 1 つの命令につき必ず 1 つのフェンスを出す。よって
#   「.re に現れた逐語系命令の並び」と「.md のフェンスの並び」は 1 対 1 になる。
#   数が合わない章は**何もしない**（当て推量で違う種別を被せない）。
# ================================================================

require_relative 'markdown_converter'
require_relative 'sideimage_restorer'

module VivlioStarter
  module CLI
    module Import
      # //output・//cmd の囲みの復元
      module VerbatimRestorer
        module_function

        # 1 命令＝1 フェンスを出す Re:VIEW の逐語系ブロック（出現順の照合に使う）
        CODE_DIRECTIVES = %w[list listnum emlist emlistnum source cmd output terminal].freeze

        # 囲み直す種別。list 系はソースコードなので素のフェンスのままでよい
        WRAP_CLASSES = { 'output' => 'output', 'cmd' => 'terminal', 'terminal' => 'terminal' }.freeze

        DIRECTIVE_LINE = %r{\A//([a-z]+)(?:\[|\{)}
        FENCE_OPEN = /\A(`{3,})\S/
        REVIEW_COMMENT = /\A\#@\#/

        # temp/ の Markdown に対して逐語ブロックの囲みを復元する
        def restore!(temp_dir, starter_dir)
          re_dir = SideimageRestorer.review_contents_dir(starter_dir)
          return unless Dir.exist?(re_dir)

          restored = Dir.glob(File.join(temp_dir, '*.md')).sum do |md_path|
            re_path = File.join(re_dir, "#{File.basename(md_path, '.md')}.re")
            File.exist?(re_path) ? restore_chapter!(md_path, re_path) : 0
          end

          Common.log_info("  実行結果・端末の囲みを #{restored} 件復元しました") if restored.positive?
        end

        # 1 章ぶんを復元し、復元できた件数を返す
        def restore_chapter!(md_path, re_path)
          names = directive_names(File.readlines(re_path, encoding: 'utf-8'))
          return 0 if names.none? { WRAP_CLASSES.key?(it) }

          lines = File.readlines(md_path, encoding: 'utf-8')
          fences = fence_spans(lines)
          return 0 unless aligned?(names, fences, md_path)

          wrap_fences!(lines, names, fences).tap do |count|
            File.write(md_path, lines.join, encoding: 'utf-8') if count.positive?
          end
        end

        # .re に現れた逐語系命令の名前を出現順に返す
        def directive_names(re_lines)
          re_lines.filter_map do |line|
            next if REVIEW_COMMENT.match?(line)

            name = DIRECTIVE_LINE.match(line.to_s.chomp)&.[](1)
            name if CODE_DIRECTIVES.include?(name)
          end
        end

        # .md のフェンスを [開き行, 閉じ行] の並びで返す
        def fence_spans(lines)
          spans = []
          index = 0

          while index < lines.size
            match = /\A(`{3,})/.match(lines[index].chomp)
            unless match
              index += 1
              next
            end

            close = MarkdownConverter.closing_fence_index(lines, index + 1, match[1])
            spans << [index, [close, lines.size - 1].min]
            index = close + 1
          end

          spans
        end

        # 数が合わなければ当て推量をせず、章を丸ごと見送る
        def aligned?(names, fences, md_path)
          return true if names.size == fences.size

          Common.log_warn(
            "  #{File.basename(md_path)}: 逐語ブロックの数が原稿と合わないため（原稿 #{names.size} / 変換後 #{fences.size}）、" \
            '実行結果の囲みを復元できませんでした。',
            detail: '対処: 実行結果のブロックを :::{.output} … ::: で囲んでください（22 章「実行結果」）。'
          )
          false
        end

        # 行番号がずれないよう後ろから囲む
        def wrap_fences!(lines, names, fences)
          targets = names.each_with_index.filter_map { |name, i| [fences[i], WRAP_CLASSES[name]] if WRAP_CLASSES[name] }

          targets.reverse_each do |(open_index, close_index), klass|
            lines[close_index] = "#{lines[close_index].chomp}\n:::\n"
            lines.insert(open_index, ":::{.#{klass}}\n")
          end

          targets.size
        end
      end
    end
  end
end
