# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/pre_process/markdown_preprocessor'
require 'vivlio_starter/cli/token_resolver'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 画像の枠 `{border=on}` / `{border=off}`（改善案.md #4）。
      #
      # 著者は値つきの属性（`{width=30% align=right border=off}`）で書き、前処理が内部クラス
      # （vs-bordered / vs-borderless）へ読み替える。単独の画像には既定で枠が付くので、
      # border=off がその枠を外す。旧記法の `.bordered` は撤去し、見つけたら直し方を知らせる。
      class ImageBorderTest < Minitest::Test
        def setup
          @temp_dir = Dir.mktmpdir('image_border_test')
          @md_path = File.join(@temp_dir, '50-sample.md')
          File.write(@md_path, "# 見出し\n")
          @entry = CLI::TokenResolver::Entry.new(
            number: '50', slug: 'sample', kind: :chapter, label: 'サンプル',
            path: @md_path, exists: true, in_catalog: true, valid: true
          )
          IssueRegistry.reset!
        end

        def teardown
          IssueRegistry.reset!
          FileUtils.rm_rf(@temp_dir)
        end

        # --- 読み替え ---

        def test_should_turn_border_off_into_borderless_class
          assert_equal "![](a.webp){width=30% align=right .vs-borderless}\n",
                       transform("![](a.webp){width=30% align=right border=off}\n")
        end

        def test_should_turn_border_on_into_bordered_class
          assert_equal "文中の ![](a.webp){.vs-bordered width=10%} です。\n",
                       transform("文中の ![](a.webp){border=on width=10%} です。\n")
        end

        # 記法を解説するコード例は書き換えない
        def test_should_leave_code_examples_untouched
          source = "```markdown\n![](a.webp){border=off}\n```\n\n`{border=on}` と書きます。\n"

          assert_equal source, transform(source)
        end

        # 不正な値は読み替えない（validate_image_borders! が知らせる）
        def test_should_leave_invalid_values_as_they_are
          assert_equal "![](a.webp){border=yes}\n", transform("![](a.webp){border=yes}\n")
        end

        # --- 点検 ---

        def test_should_warn_retired_bordered_with_a_rewrite
          warnings = validate("本文\n\n![](a.webp){.bordered width=60%}\n")

          assert_equal 1, warnings.size
          message, detail = warnings.first

          assert_includes message, '50-sample.md:3'
          assert_includes detail, '{.bordered width=60%} を {border=on width=60%} に'
        end

        def test_should_warn_retired_bordered_container
          warnings = validate(":::{.bordered}\n![](a.webp)\n:::\n")

          assert_equal 1, warnings.size
          assert_includes warnings.first[0], ':::{.bordered} は撤去しました'
        end

        def test_should_warn_invalid_border_value
          warnings = validate("![](a.webp){border=yes}\n")

          assert_equal 1, warnings.size
          assert_includes warnings.first[0], 'border=yes'
          assert_includes warnings.first[1], 'border=on'
        end

        def test_should_not_warn_valid_notation_or_code_examples
          source = <<~MD
            ![](a.webp){width=30% border=off}
            ![](b.webp){border=on}

            `{.bordered}` は旧記法です。

            ```markdown
            ![](c.webp){.bordered}
            ```
          MD

          assert_empty validate(source)
        end

        private

        def preprocessor(markdown)
          MarkdownPreprocessor.new(@md_path, @entry).tap { it.context.content = markdown }
        end

        def transform(markdown)
          pre = preprocessor(markdown)
          pre.send(:transform_image_borders!)
          pre.context.content
        end

        # 🟡 の [メッセージ, detail] を集めて返す
        def validate(markdown)
          warnings = []
          Common.stub(:log_warn, ->(message, detail: nil) { warnings << [message, detail] }) do
            preprocessor(markdown).send(:validate_image_borders!)
          end
          warnings
        end
      end
    end
  end
end
