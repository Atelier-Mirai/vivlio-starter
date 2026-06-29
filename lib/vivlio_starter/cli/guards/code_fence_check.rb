# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # contents/*.md のコードフェンス（``` / ~~~）の開始・終了が揃っているかを
      # ビルド前に検出して警告する。閉じ忘れや余分なフェンスがあると、以降の本文が
      # コード扱い（またはその逆）になり、ビルドの体裁や校正が崩れる。
      #
      # きっかけ: 同じバッククォート数でフェンスを入れ子にした原稿
      # （外: ```markdown ／ 内: ```css）が閉じきらず、以降の校正・体裁がずれた。
      # `vs lint` のスペルチェックが大量に誤検出して発覚した。
      #
      # 判定: 行頭の ```（3 連以上）/ ~~~（3 連以上）を「フェンス区切り」と数え、
      # 総数が奇数なら「閉じ忘れ／余分」と見なす。整形式の原稿では、入れ子を含め
      # 常に偶数になる（コード例の中で ``` を示す入れ子は、外側を ```` 4 連にすれば
      # 内側の ``` 2 行と合わせて偶数で整合する）。
      # 重大度はエラー（ビルドしても意図通りにならないため、画像名チェック等と同様に
      # ビルド前に停止させる）。
      class CodeFenceCheck < BaseCheck
        # 行頭（先頭空白許容）の 3 連以上のバックティック or チルダ。
        FENCE_LINE = /\A\s*(?:`{3,}|~{3,})/

        # @return [Array<Violation>] エラーの配列（合格なら空配列）
        def validate
          markdown_files.filter_map { |path| check_file(path) }
        end

        private

        def markdown_files
          Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).sort
        end

        # 1 ファイルのフェンス区切り行を数え、奇数なら警告を返す（偶数なら nil）。
        def check_file(path)
          fence_lines = []
          File.foreach(path).with_index(1) do |line, lineno|
            fence_lines << lineno if line.match?(FENCE_LINE)
          end
          return nil if fence_lines.size.even?

          error(
            "コードフェンス（```）の開始と終了の数が合いません（#{fence_lines.size} 個＝奇数）: #{path}",
            detail: fence_violation_detail(fence_lines)
          )
        end

        # 修正案＋出現箇所（フェンス行番号）を行配列で返す。
        def fence_violation_detail(fence_lines)
          [
            '→ どこかでフェンスの閉じ忘れ、または余分な ``` があります',
            '→ コード例の中で ``` 自体を示す入れ子は、外側を ```` (4 連バッククォート) にしてください',
            "フェンス行: #{fence_lines.join(', ')}"
          ]
        end
      end
    end
  end
end
