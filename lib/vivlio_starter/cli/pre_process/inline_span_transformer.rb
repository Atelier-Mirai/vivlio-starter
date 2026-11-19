# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/inline_span_transformer.rb
# ================================================================
# 責務:
#   行内の属性の記法 `[文字]{.class}` を `<span class="class">文字</span>` にする
#   （v2-architecture-spec.md §7.1 の D 型。Pandoc の bracketed span と同じ書き方）。
#   傍点 `[文字]{.sesame}` と縦中横 `[12]{.tcy}` はこの記法で書く（novel-vertical-spec.md §5.1）。
#
# 受ける形:
#   - `{…}` の中はクラスだけ（`{.a}`・`{.a .b}`）。`#id` や `key=value` を含むものは読まない
#     （受ける範囲を広げるのは後からできるが、狭めると原稿の意味が変わる）。
#   - `[…]` の中は 1 段まで角かっこを入れ子にできる。`[[用語]]{.sesame}` は、索引語に傍点を付ける。
#   - 画像（`![…]`）・インライン脚注（`^[…]`）・`\[` で始まるものは読まない。
#   - コードの中は置き換えない（Masking）。
#   - 行末の `{.text-right}`・`{.aki}`・`{.small}` などは、段落に付けるクラスの記法（1.x から）なので
#     読まない。`…[用語]{.aki}` は、1.x と同じく段落の下を空ける（PARAGRAPH_CLASSES）。
#
# 索引の `[用語]` は `]` の直後に `{.` が続くものを読まない（IndexMarkup の除外）。
# CSS に無いクラスは Guards::ContainerClassCheck が 🟡 で示す。
# ================================================================

require_relative '../masking'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # `[文字]{.class}` を span にする
      module InlineSpanTransformer
        CLASS_NAME = /[A-Za-z_][\w-]*/
        CLASS_TOKEN = /\.(#{CLASS_NAME})/

        # `[文字]{.a .b}`。text は角かっこの中、classes は `{` と `}` の間
        PATTERN = /
          (?<![!^\\])
          \[(?<text>(?:[^\[\]\n]|\[[^\[\]\n]*\])+)\]
          \{(?<classes>[ \t]*\.#{CLASS_NAME}(?:[ \t]+\.#{CLASS_NAME})*[ \t]*)\}
        /x

        # 段落の末尾に書いて段落に付けるクラス（1.x からの記法）。寄せは前処理の
        # MarkdownPreprocessor#transform_text_right_inlines!、空き・小さい字・出典は後処理の
        # ReplacementRules::SPACING_CLASS_RULES・PARAGRAPH_CLASS_RULES が読む。`…[用語]{.aki}` の
        # `{.aki}` は段落のクラスなので、行内の属性として読まない
        PARAGRAPH_CLASSES = %w[right text-right text-center text-left aki aki2 small references].freeze
        PARAGRAPH_ATTRIBUTE = /\{\.(?:#{PARAGRAPH_CLASSES.join('|')})\}[ \t]*\z/

        # 行内の属性の 1 か所。classes はクラス名の並び、source は原稿の字面
        Span = Data.define(:text, :classes, :source)

        module_function

        # @param content [String] 章の Markdown
        # @return [String] 行内の属性を span にした Markdown
        def transform(content)
          return content unless content.include?(']{')

          protected_text, spans = Masking.protect_code(content)
          converted = protected_text.gsub(PATTERN) do
            match = ::Regexp.last_match
            next match[0] if paragraph_attribute?(match)

            %(<span class="#{classes_of(match[:classes]).join(' ')}">#{match[:text]}</span>)
          end
          Masking.restore_code(converted, spans)
        end

        # 原稿の 1 行（コードの外）の行内の属性を並べる。
        # 原稿をそのまま読む検査（未知のクラス・vs upgrade の走査）が使う
        # @param line [String]
        # @return [Array<Span>]
        def each_span(line)
          prose = Masking.strip_inline_code(line.chomp)
          prose.to_enum(:scan, PATTERN).filter_map do
            match = ::Regexp.last_match
            next if paragraph_attribute?(match)

            Span.new(text: match[:text], classes: classes_of(match[:classes]), source: match[0])
          end
        end

        def classes_of(text) = text.scan(CLASS_TOKEN).flatten

        # 行末の、段落に付けるクラス（`…[用語]{.aki}` の `{.aki}`）か
        def paragraph_attribute?(match)
          match[0].match?(PARAGRAPH_ATTRIBUTE) && match.post_match[/\A[^\n]*/].strip.empty?
        end
      end
    end
  end
end
