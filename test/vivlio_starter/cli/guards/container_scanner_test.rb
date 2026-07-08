# frozen_string_literal: true

# ================================================================
# Test: guards/container_scanner_test.rb
# ================================================================
# テスト対象:
#   Guards::ContainerScanner（lib/vivlio_starter/cli/guards/container_scanner.rb）
#
# 検証内容:
#   - フェンス内（``` / ~~~ / 4 連）の ::: を拾わない
#   - HTML コメント内（単一行・複数行）の ::: を拾わない
#   - 行頭でないインラインコードの `:::{.class}` を拾わない
#   - 複数クラス・属性トークン（scale=60%）の分解
#   - インデントされた ::: を拾う
#   - 行番号が原稿の行番号と一致する
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class ContainerScannerTest < Minitest::Test
      # フェンス内の記法解説（```markdown の中の :::）は走査対象外
      def test_should_ignore_directives_inside_code_fences
        directives = scan(<<~MD)
          # 記法

          ```markdown
          :::{.クラス名}
          ここに内容を書く
          :::
          ```

          :::{.column}
          本文
          :::
        MD

        assert_equal %i[open close], directives.map(&:kind)
        assert_equal [['column'], []], directives.map(&:classes)
        assert_equal [9, 11], directives.map(&:line_number)
      end

      # 4 連バッククォートの入れ子フェンスも内側を走査対象外にする
      def test_should_ignore_directives_inside_nested_four_backtick_fence
        directives = scan(<<~MD)
          ````markdown
          ```
          :::{.notice}
          ```
          ````
        MD

        assert_empty directives
      end

      # チルダフェンスの内側も走査対象外
      def test_should_ignore_directives_inside_tilde_fence
        directives = scan("~~~\n:::{.notice}\n~~~\n")

        assert_empty directives
      end

      # 複数行の HTML コメント内（会話文 TODO の :::{.talk}）は走査対象外
      def test_should_ignore_directives_inside_multiline_html_comment
        directives = scan(<<~MD)
          <!--
          TODO: 会話文記法は未確定
          :::{.talk}
          -->

          :::{.note}
          本文
          :::
        MD

        assert_equal [['note'], []], directives.map(&:classes)
        assert_equal [6, 8], directives.map(&:line_number)
      end

      # 単一行の HTML コメントも走査対象外
      def test_should_ignore_directives_inside_single_line_html_comment
        directives = scan("<!-- :::{.talk} -->\n")

        assert_empty directives
      end

      # 行頭でないインラインコード（`:::{.class}` など）は拾わない
      def test_should_ignore_inline_code_directive_not_at_line_start
        directives = scan("- Vivliostyle 拡張記法（`:::{.class}` など）内の語も除外されます。\n")

        assert_empty directives
      end

      # ::: と { の間に空白があっても開始行として扱い、複数クラスを分解する
      def test_should_split_multiple_classes_with_space_before_brace
        directives = scan("::: {.img-text .align-center}\n:::\n")

        assert_equal %w[img-text align-center], directives.first.classes
        assert_empty directives.first.attributes
      end

      # scale=60% / shift-y=20% は属性であってクラス名ではない
      def test_should_separate_attribute_tokens_from_class_names
        directives = scan(":::{.table-rotate scale=60% shift-y=20%}\n:::\n")

        assert_equal ['table-rotate'], directives.first.classes
        assert_equal ['scale=60%', 'shift-y=20%'], directives.first.attributes
      end

      # インデントされた ::: も経路 B では div になるため拾う
      def test_should_detect_indented_directives
        directives = scan("  :::{.note}\n  :::\n")

        assert_equal %i[open close], directives.map(&:kind)
      end

      # 4 個以上のコロンも開始・終了として扱う
      def test_should_accept_four_or_more_colons
        directives = scan("::::{.note}\n::::\n")

        assert_equal %i[open close], directives.map(&:kind)
      end

      private

      def scan(markdown)
        Dir.mktmpdir('vs-container-scanner') do |dir|
          path = File.join(dir, 'chapter.md')
          File.write(path, markdown)
          Guards::ContainerScanner.scan(path)
        end
      end
    end
  end
end
