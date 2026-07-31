# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/heading_segmenter.rb
# ================================================================
# 責務:
#   見出しを「折り返してよい位置」で分割する。
#
# なぜ必要か:
#   日本語の複合語は CSS の word-break: auto-phrase でも割れない。
#   「コマンドラインオプション」は文節としては 1 つなので分割点が無く、
#   組版エンジンは文字間の任意の位置で折る——結果「コマンドラインオプ／ション」の
#   ように語の途中で割れる。読者が期待するのは「コマンドライン／オプション」。
#
#   形態素解析（MeCab）で語の境界を取れば、その境界だけを折返し候補にできる。
#   PDF は各語を white-space: nowrap で括り、EPUB の合成画像は Ruby の行分割が
#   この境界を使う。どちらも「語の途中では折らない」という同じ規則になる。
#
# MeCab が無い環境:
#   分割せず 1 要素の配列を返す（呼び出し側は従来どおりの折返しへ縮退する）。
#   組版が MeCab の有無で変わるのは避けたい性質だが、変わるのは「折返し位置が
#   より自然になるか否か」だけで、内容・寸法・ページ数には影響しない。
#   YomiInferrer と同じ Natto を使い、可用性判定・警告もそこへ委譲する。
# ================================================================

require_relative 'common'

module VivlioStarter
  module CLI
    # 見出しを折返し可能な語へ分割するモジュール
    module HeadingSegmenter
      # 見出しとして現実的な長さの上限（これを超えるものは解析しない）
      MAX_LENGTH = 200

      module_function

      # 見出しを語の配列へ分割する。
      # 分割できない（MeCab 不在・空文字・長すぎる）場合は [text] を返す。
      # @param text [String]
      # @return [Array<String>] 連結すると元の文字列に戻る語の配列
      def segment(text)
        source = text.to_s
        return [source] if source.empty? || source.length > MAX_LENGTH
        return [source] unless inferrer.available?

        words = collect_surfaces(source)
        words.join == source ? merge_unbreakable(words) : [source]
      rescue StandardError => e
        Common.log_debug("見出しの語分割に失敗（そのまま扱います）: #{e.message}")
        [source]
      end

      # MeCab の表層形を並べる（読みは使わないので feature は見ない）。
      # MeCab は空白を落とすので、原文を走査して落ちた分を**直前の語の末尾**へ戻す
      # （語頭へ付けると行頭に空白が来る）。連結して原文に戻ることを呼び出し側が検証する。
      def collect_surfaces(text)
        surfaces = []
        pos = 0
        inferrer.send(:mecab).parse(text) do |node|
          next if node.is_eos? || node.surface.empty?

          index = text.index(node.surface, pos) or next
          skipped = text[pos...index]
          surfaces[-1] = surfaces[-1] + skipped if !skipped.empty? && !surfaces.empty?
          surfaces << (surfaces.empty? ? skipped + node.surface : node.surface)
          pos = index + node.surface.length
        end
        surfaces[-1] = surfaces[-1] + text[pos..] if pos < text.length && !surfaces.empty?
        surfaces
      end

      # 直前の語と離してはいけない語を接着する。
      # 助詞・助動詞・記号だけの語や 1 文字の送り仮名を単独で行頭へ送ると、
      # かえって不自然に見える（「章の／管理」より「章の管理」）。
      def merge_unbreakable(words)
        merged = words.each_with_object([]) do |word, acc|
          if acc.empty? || !glue_to_previous?(word)
            acc << word.dup
          else
            acc[-1] << word
          end
        end
        glue_open_brackets(merged)
      end

      # 行頭に単独で置きたくない語か。約物・閉じ括弧・1〜2 文字の仮名（助詞等）。
      GLUE_PATTERN = /\A[ぁ-んー、。，．・：；？！）］｝」』〉》】〕”’]+\z/
      # 行末に単独で置きたくない語（開き括弧）は次の語へ接着する
      OPEN_BRACKET_PATTERN = /\A[（［｛「『〈《【〔“‘]+\z/

      def glue_to_previous?(word)
        word.length <= 2 && word.match?(GLUE_PATTERN)
      end

      def glue_open_brackets(words)
        words.reverse.each_with_object([]) do |word, acc|
          if acc.empty? || !word.match?(OPEN_BRACKET_PATTERN)
            acc << word.dup
          else
            acc[-1] = word + acc[-1]
          end
        end.reverse
      end

      # YomiInferrer の MeCab インスタンス・可用性判定を共有する
      # （MeCab の初期化と不在時の案内を 2 か所に持たない）。
      def inferrer
        require_relative 'index/yomi_inferrer'
        @inferrer ||= IndexCommands::YomiInferrer.new
      end
    end
  end
end
