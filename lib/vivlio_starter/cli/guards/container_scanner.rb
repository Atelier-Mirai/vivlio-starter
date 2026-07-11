# frozen_string_literal: true

require_relative '../masking'

module VivlioStarter
  module CLI
    module Guards
      # contents/*.md の `:::` コンテナ記法（開始行・終了行）を、行番号つきで拾い出す。
      # ContainerFenceCheck（開閉バランス）と ContainerClassCheck（未知クラス名）が共有する。
      #
      # なぜ Masking.each_prose_line なのか:
      #   フェンス内の `:::`（記法解説のコード例）を数えてはならない一方、報告する行番号は
      #   原稿そのものの行番号でなければならない。each_prose_line は「コード行を飛ばしつつ
      #   通し行番号を維持する」唯一の実装であり、この二要件を同時に満たす。
      #   Masking.protect_code は使えない。フェンスをプレースホルダ 1 個に畳んで行番号を崩し、
      #   さらに INLINE_CODE_SPAN が /m 付きのため孤立したバッククォート対が複数行を飲み込む。
      #   （実測: protect_code 経由だと contents/41-book-yml.md が「閉じ忘れ」と誤検出された）
      module ContainerScanner
        # 開始行。`:::{.a .b}` / `::: {.a scale=60%}` の両方を受ける。
        # 経路 B（組み込み置換ルール ReplacementRules）は行頭の空白を問わないため lstrip 後に判定する。
        OPEN = /\A:{3,}\s*\{(?<body>[^}]*)\}/
        # 終了行。`:::` / `::::` のみの行。
        CLOSE = /\A:{3,}\s*\z/

        # 走査結果の 1 件。kind は :open または :close。
        # classes / attributes は :close では常に空配列。
        Directive = Data.define(:line_number, :kind, :classes, :attributes)

        module_function

        # @param path [String] contents 配下の Markdown ファイルパス
        # @return [Array<Directive>] 出現順の走査結果
        def scan(path)
          directives = []
          in_comment = false

          Masking.each_prose_line(File.read(path, encoding: 'utf-8')) do |line, lineno|
            in_comment, skip = comment_state(in_comment, line)
            next if skip

            directive = parse(line.lstrip, lineno)
            directives << directive if directive
          end

          directives
        end

        # HTML コメント（`<!-- … -->`）内かどうかを 1 行ずつ遷移させる。
        # 会話文記法の TODO（contents/22-extentions.md）が `:::{.talk}` をコメント内に抱えており、
        # これを実在の記法として数えると偽陽性になる。
        # @return [Array(Boolean, Boolean)] 次行へ持ち越す状態と、この行を読み飛ばすか
        def comment_state(in_comment, line)
          return [!line.include?('-->'), true] if in_comment
          return [!line.include?('-->'), true] if line.include?('<!--')

          [false, false]
        end

        # 行頭が `:::` なら Directive を返す（そうでなければ nil）。
        def parse(stripped, lineno)
          if (matched = stripped.match(OPEN))
            classes, attributes = split_tokens(matched[:body])
            Directive.new(line_number: lineno, kind: :open, classes:, attributes:)
          elsif stripped.match?(CLOSE)
            Directive.new(line_number: lineno, kind: :close, classes: [], attributes: [])
          end
        end

        # `{…}` の中身をクラス名と属性トークンに分ける。
        # 先頭の `.` は任意（経路 B の正規表現が `\.?` で両方通すため）。
        # `scale=60%` / `shift-y=20%` は経路 A が解する属性であり、クラス名ではない。
        def split_tokens(body)
          attributes, class_tokens = body.split.partition { it.include?('=') }
          [class_tokens.map { it.delete_prefix('.') }, attributes]
        end
      end
    end
  end
end
