# frozen_string_literal: true

# ================================================================
# Module: BookCommentFixer
# ================================================================
# 責務:
#   config/book.yml に残った、誤りを直す前の説明コメントを、今の雛形の文言に直す（改善案 #187）。
#   vs upgrade の「著者データの整理」が使う。
#
# なぜ要るか:
#   vs upgrade が book.yml に手を入れるのは、廃止したキーと、雛形で増えたキーだけだった。
#   雛形のコメントの誤りを直しても今ある本には届かず、`images/` に置けば使えると読める
#   コメントが残って、画像が見つからない本ができていた。
#
# 直す行の決め方:
#   book.yml には著者が書き足したコメントもあるので、雛形のコメントで丸ごと置き換えない。
#   CORRECTIONS に載せた古い文言と、コメントの中身（`#` の後ろ・前後の空白を除く）が
#   一字一句同じ行だけを直す。言い回しだけの違いは載せない（意味の誤りだけを直す）。
#   行の `#` より前（キーと値・字下げ）と、`#` の後ろの空白はそのまま残す。
# ================================================================

module VivlioStarter
  module CLI
    module BookCommentFixer
      extend self

      # 雛形で誤りを直したコメント。old は直す前の文言、new は今の雛形の文言、key は計画の表に出す場所
      Correction = Data.define(:key, :old, :new)

      # 誤りを直したら、ここへ 1 行足す
      CORRECTIONS = [
        Correction.new(key: '冒頭の一覧の verify',
                       old: '• verify       : 原稿の検証（画像パス、裸URL、外部URL）',
                       new: '• verify       : 原稿の検証（画像パス、外部URL）'),
        Correction.new(key: 'theme.frontispiece.image',
                       old: 'images/内の独自画像も指定可',
                       new: 'stylesheets/images/ の独自画像も指定可'),
        Correction.new(key: 'theme.frontispiece.edge_inset',
                       old: '扉絵を紙の端から内側へ引っ込める量',
                       new: '扉絵の上下と紙の端の間の余白')
      ].freeze

      # 行のコメント（`#` と、その後ろの空白と中身）。値の中の `#`（`"#3a9d5d"`）で切らないよう、
      # `#` の前は空白か行頭に限る
      COMMENT = /(?<=\A|\s)#(?<space>[ \t]*)(?<body>.*?)[ \t]*$/

      # 直す行
      # @param text [String] book.yml の中身
      # @return [Array<Correction>] 直す行のコメント（同じ文言が 2 行あれば 2 つ）
      def corrections(text) = text.each_line.filter_map { correction_for(it) }

      # 古いコメントを直した book.yml の中身
      # @param text [String]
      # @return [String]
      def apply(text)
        text.each_line.map do |line|
          correction = correction_for(line)
          next line unless correction

          line.sub(COMMENT) { "##{Regexp.last_match[:space]}#{correction.new}" }
        end.join
      end

      private

      def correction_for(line)
        body = line[COMMENT, :body] or return nil
        CORRECTIONS.find { it.old == body }
      end
    end
  end
end
