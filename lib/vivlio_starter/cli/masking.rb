# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/masking.rb
# ================================================================
# 責務:
#   Markdown のコード領域（フェンス／インライン）解釈の「唯一の実装」。
#   索引・校正・メトリクス・画像パス検証など横断的に必要となる
#   「コードブロックを処理対象から外す」ニーズを、ただ一つの状態機械に集約する。
#
# なぜ状態機械なのか:
#   素朴な /```...```/ の対消しや単純トグルは、地の文に現れるインライン ```
#   や、可変長フェンスの入れ子（```` の中の ``` など）で内外が反転する潜在バグを
#   持つ。行頭フェンスだけを数える状態機械に揃えることで、可変長フェンス
#   （```/````/~~~）と入れ子に一貫して耐える。IndexCommands::CodeBlockStripper の
#   意味論を移植・一般化した原器。
#
# 仕様: docs/specs/vivlioverso-foundation-workplans.md P1
# ================================================================

module VivlioStarter
  module CLI
    # Markdown のコード領域解釈の唯一実装。
    module Masking
      module_function

      # 行頭フェンス（``` または ~~~ を 3 連以上）のマーカー。
      FENCE = /\A(?:`{3,}|~{3,})/

      # protect_code が用いるプレースホルダの接頭辞（既存 MarkdownUtils と互換）。
      CODE_SPAN_PLACEHOLDER_PREFIX = '__VS_CODE_SPAN__'

      # インラインコードスパン（N 個の連続バッククォート同士の対）。
      # (?<!`) / (?!`) で開き・閉じの両端が「ちょうど N 個のラン」であることを担保し、
      # ``foo`bar`` のように内部にバッククォートを含むケースも 1 スパンとして保護する。
      INLINE_CODE_SPAN = /(?<!`)(`+)(?!`).+?(?<!`)\1(?!`)/m

      # --- (a) コード外の行だけを走査する -----------------------------------

      # コード（フェンス区切り行・フェンス内容行）を除いた「地の文」の行だけを
      # 行番号（1 始まり）つきで yield する。ブロック未指定なら Enumerator を返す。
      # 行番号は入力テキスト全体に対する通し番号で、コード行を飛ばしても維持される。
      def each_prose_line(text)
        return enum_for(:each_prose_line, text) unless block_given?

        scan_lines(text) do |line, lineno, in_code|
          yield line, lineno unless in_code
        end
      end

      # --- (b) コードを除去したテキストを返す（行数維持） -------------------

      # フェンス・インラインコードを取り除いたテキストを返す。
      # フェンス（区切り行・内容行）は空行に置換して行数を保つため、周辺文脈の
      # 行対応は崩れない。インラインコードは空白 1 文字へ潰す。
      def strip_code(text)
        stripped = +''
        scan_lines(text) do |line, _lineno, in_code|
          stripped << (in_code ? "\n" : line)
        end
        strip_inline_code(stripped)
      end

      # インラインコード `...` を空白に置き換える。
      def strip_inline_code(text) = text.gsub(/`[^`\n]+`/, ' ')

      # --- (c) トップレベルのフェンスブロックを選択的に置換する -------------

      # トップレベルのフェンスドコードブロック（開始区切り〜終了区切り）を 1 つずつ
      # yield し、戻り値で置き換える。nil を返したブロックは原文のまま残す。
      # yield には開始フェンス行の行番号（1 始まり）も渡す——著者向け警告に
      # 「ファイル:行」を添えるため（warning-messages の流儀）。
      #
      # コード保護（protect_code）より前段で特定言語のフェンスを横取りする変換
      # （例: ```mermaid の図化）のための公開 API。フェンス解釈（可変長・入れ子・
      # ~~~・include: 除外・未終了は素通し）はこのモジュールの状態機械に一元化され、
      # 独自の再実装を作らせないための入り口でもある（P1「唯一の実装」）。
      #
      # @param text [String] 処理対象テキスト
      # @yieldparam block [String] フェンスブロック全体（開始行〜終了行。末尾改行は含まない）
      # @yieldparam lineno [Integer] 開始フェンス行の行番号（1 始まり）
      # @yieldreturn [String, nil] 置換文字列（nil なら置換しない）
      # @return [String] 置換後のテキスト
      def replace_top_level_fences(text, &) = replace_fenced_blocks(text, &)

      # --- (d) コード退避 → 処理 → 復元（プレースホルダ方式） ---------------

      # コードフェンスブロックとインラインコードスパンを一時プレースホルダへ退避し、
      # 後続のテキスト変形処理から除外できるようにする。
      # フェンス判定は状態機械へ統一（可変長・入れ子に追従）。
      # @return [Array(String, Hash)] 退避後テキストと { placeholder => 原文 } の対応表
      def protect_code(text)
        spans = {}
        counter = 0

        # 第 2 引数はフェンス経由でのみ渡る行番号（gsub 経由の呼び出しでは省略される）
        alloc = lambda do |chunk, _lineno = nil|
          key = "#{CODE_SPAN_PLACEHOLDER_PREFIX}#{counter}__"
          spans[key] = chunk
          counter += 1
          key
        end

        # まずフェンスドコードブロック全体を退避（インラインコードより先に処理）。
        protected_text = replace_fenced_blocks(text, &alloc)

        # 次にインラインコードスパンを退避。
        protected_text = protected_text.gsub(INLINE_CODE_SPAN, &alloc)

        [protected_text, spans]
      end

      # protect_code で退避したコードを元に戻す。
      # 後から退避したインラインの原文が、先に退避したフェンスのプレースホルダを
      # 内包しうる（行を跨ぐバッククォート対がフェンス置換後のプレースホルダを
      # 巻き込むケース）。この入れ子を正しく巻き戻すため、挿入の逆順（LIFO /
      # reverse_each）で外側→内側の順に開く。FIFO だと未復元のプレースホルダが残留する。
      def restore_code(text, spans)
        restored = text.to_s
        spans.reverse_each do |placeholder, original|
          restored = restored.gsub(placeholder) { original }
        end
        restored
      end

      # --- 内部: 行単位の状態機械 -------------------------------------------

      # 各行を「コード（in_code=true）／地の文（false）」に分類しつつ走査する中核。
      # フェンス区切り行（開始・終了とも）と、その内側の行を in_code=true とする。
      # 閉じ判定は「開始と同じ種類・同じ長さ以上」（短い入れ子フェンスでは閉じない）。
      # yields (line, lineno, in_code)
      def scan_lines(text)
        return enum_for(:scan_lines, text) unless block_given?

        fence = nil # 開いているフェンスのマーカー（nil = コード外）
        text.each_line.with_index(1) do |line, lineno|
          marker = fence_marker(line)

          if fence.nil?
            if marker
              fence = marker
              yield line, lineno, true # 開始フェンス
            else
              yield line, lineno, false # 地の文
            end
          elsif marker && closing_fence?(marker, fence)
            fence = nil
            yield line, lineno, true # 終了フェンス
          else
            yield line, lineno, true # フェンス内本文（短い入れ子フェンス含む）
          end
        end
      end
      private_class_method :scan_lines

      # 行頭（先頭空白許容）のフェンスマーカーを返す（フェンスでなければ nil）。
      # ```include: は単一行のインクルード指令でありフェンスではないので除外する。
      def fence_marker(line)
        stripped = line.lstrip
        return nil if stripped.start_with?('```include:')

        stripped[FENCE]
      end
      private_class_method :fence_marker

      # 閉じフェンスとして妥当か（同種・同連長以上）。
      def closing_fence?(marker, opener) = marker[0] == opener[0] && marker.length >= opener.length
      private_class_method :closing_fence?

      # フェンスドコードブロック（開始区切り〜同種・同連長以上の終了区切りまで）を
      # 1 チャンクとして yield の戻り値で置き換える。nil が返ったブロックは原文のまま
      # 残す（replace_top_level_fences の選択的置換）。未終了のフェンスは（正規表現方式の
      # 従来挙動に合わせ）退避せずそのまま残す。
      #
      # 終了区切り行の改行はチャンクへ含めず、プレースホルダの外側に残す。
      # 改行ごと退避すると後続行がプレースホルダと同一行に癒着し（例: `__VS_CODE_SPAN__13__:::`）、
      # 行頭 `:::` を前提とするコンテナ変換などの行アンカー処理が退避中テキストで誤動作する
      # （book-card がコンテナごと `.output` の中身として飲み込まれた実バグの原因）。
      # 復元はプレースホルダ→チャンクの置換なので、改行を外に置いても原文と同一に戻る。
      def replace_fenced_blocks(text)
        out = +''
        block = nil # 蓄積中のフェンスブロック（nil = ブロック外）
        fence = nil
        block_lineno = nil # 蓄積中ブロックの開始行番号（反復間で保持するためループ前に宣言）
        lineno = 0

        text.each_line do |line|
          lineno += 1
          marker = fence_marker(line)

          if fence.nil?
            if marker
              fence = marker
              block = +line
              block_lineno = lineno
            else
              out << line
            end
          else
            block << line
            if marker && closing_fence?(marker, fence)
              trailing = block.chomp!("\n") ? "\n" : ''
              out << (yield(block, block_lineno) || block) << trailing
              fence = nil
              block = nil
            end
          end
        end

        out << block if block # 未終了フェンスは退避せず原文のまま
        out
      end
      private_class_method :replace_fenced_blocks
    end
  end
end
