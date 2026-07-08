# frozen_string_literal: true

require_relative 'container_scanner'

module VivlioStarter
  module CLI
    module Guards
      # contents/*.md の `:::` コンテナ記法の開始・終了が揃っているかを検出して停止する。
      #
      # なぜエラー（停止）なのか:
      #   `:::{.class}` は最終的に `<div class="class">` へ、残る `:::` は一律 `</div>` へ
      #   置換される（config/post_replace_list.yml）。数が合わなければ `<div>` が閉じず、
      #   以降の本文がまるごと枠の中へ飲み込まれる。CodeFenceCheck（``` の数）と同じ性質の
      #   破綻であり、ビルド前に止めるのが親切である。
      #
      # 判定: 開始（`:::{…}`）で深さ +1、終了（`:::` のみ）で −1。
      #   深さが負になれば「対応する開始がない終了」、走査後に正なら「閉じ忘れ」。
      #   入れ子（`:::{.column}` の中の `:::{.note}`）は正しく均衡と判定される。
      class ContainerFenceCheck < BaseCheck
        # @return [Array<Violation>] エラーの配列（合格なら空配列）
        def validate
          markdown_files.filter_map { check_file(it) }
        end

        private

        def markdown_files = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).sort

        # 1 ファイルを走査し、不整合があれば違反を返す（整合なら nil）。
        def check_file(path)
          directives = ContainerScanner.scan(path)
          unclosed = []  # 対応する終了がない開始行（LIFO で消費される）
          surplus  = []  # 対応する開始がない終了行

          directives.each do |directive|
            if directive.kind == :open
              unclosed << directive
            elsif unclosed.empty?
              surplus << directive.line_number
            else
              unclosed.pop
            end
          end
          return nil if unclosed.empty? && surplus.empty?

          opens, closes = directives.partition { it.kind == :open }.map(&:size)
          error(
            "コンテナ記法（:::）の開始と終了の数が合いません（開始 #{opens} 個 / 終了 #{closes} 個）: #{path}",
            detail: violation_detail(unclosed, surplus)
          )
        end

        # 修正案＋出現箇所（行番号）を行配列で返す。
        def violation_detail(unclosed, surplus)
          detail = []
          unclosed.each do |directive|
            opener = ":::{#{directive.classes.map { ".#{it}" }.join(' ')}}"
            detail << "→ #{directive.line_number} 行目の #{opener} が閉じられていません。対応する ::: を追記してください"
          end
          surplus.each do |lineno|
            detail << "→ #{lineno} 行目の ::: に対応する開始行がありません。余分な ::: を削除してください"
          end
          detail << '→ コード例の中で ::: 自体を示す場合は、フェンス（```）で囲めば数えられません'
          detail
        end
      end
    end
  end
end
