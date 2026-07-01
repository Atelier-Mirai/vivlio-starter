# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/code_block_stripper.rb
# ================================================================
# 責務:
#   Markdown からコード（フェンス／インライン）を取り除く。
#   索引・用語の候補抽出で、コード例やログ出力の断片（バーグラフ
#   `[###]`、配列リテラル `[00, 90-98, 99]` など）が索引語として
#   誤検出されるのを防ぐ。
#
# なぜ状態機械なのか:
#   素朴な /```...```/ による対消しは、地の文に現れるインライン ```
#   （例:「` ``` ` で囲んだ部分」）を余分なフェンスと誤認し、以降の
#   フェンス対が 1 つずつズレて破綻する（コードブロックの中身が地の
#   文化して誤検出される）。行頭フェンスだけを数える IndexMatchScanner
#   と同じ方式に揃え、可変長フェンス（```/````/~~~）と入れ子にも耐える。
# ================================================================

module VivlioStarter
  module CLI
    module IndexCommands
      module CodeBlockStripper
        module_function

        # 行頭フェンス（``` または ~~~ を 3 連以上）のマーカー。
        FENCE = /\A(?:`{3,}|~{3,})/

        # フェンス・インラインコードを取り除いたテキストを返す。
        # 行数は保つ（コード行は空行に置換）ため、周辺文脈の行対応は崩れない。
        def strip(content)
          strip_inline_code(strip_fenced_blocks(content))
        end

        # フェンスドコードブロックを空行に置き換える。
        def strip_fenced_blocks(content)
          fence = nil # 開いているフェンスのマーカー（nil = コード外）

          content.each_line.map do |line|
            stripped = line.lstrip
            marker = stripped[FENCE]

            # ```include: は単一行のインクルード指令でフェンスではない。
            if marker && !stripped.start_with?('```include:')
              if fence.nil?
                fence = marker
                next "\n"
              elsif marker[0] == fence[0] && marker.length >= fence.length
                # 開始と同じ種類・同じ長さ以上でのみ閉じる（短い入れ子では閉じない）。
                fence = nil
                next "\n"
              end
              # 開始より短い／別種の入れ子フェンスはコード本文として扱う
            end

            fence ? "\n" : line
          end.join
        end

        # インラインコード `...` を空白に置き換える。
        def strip_inline_code(text)
          text.gsub(/`[^`\n]+`/, ' ')
        end
      end
    end
  end
end
