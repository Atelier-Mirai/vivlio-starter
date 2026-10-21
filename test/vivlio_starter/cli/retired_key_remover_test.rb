# frozen_string_literal: true

# ================================================================
# Test: retired_key_remover_test.rb
# ================================================================
# テスト対象:
#   RetiredKeyRemover（lib/vivlio_starter/cli/retired_key_remover.rb）
#
# 検証内容（改善案.md #114）:
#   - 書かれている廃止キーだけを拾う
#   - 廃止キーの行と、その下の入れ子だけを消し、コメント・空行・ほかのキーは残す
#   - 消した結果、下にキーが残らない親も消す
#   - 行から読み取れない書き方（流れ形式）では書き換えない（nil）
#   - 移した先のある廃止キーは、値と注釈を移した先へ写してから消す（multivolume-spec.md §3.5）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/retired_key_remover'

module VivlioStarter
  module CLI
    class RetiredKeyRemoverTest < Minitest::Test
      RETIRED = [%i[verify images], %i[verify bare_urls], %i[spellcheck extra_words], %i[lint config]].freeze

      def test_should_find_only_retired_keys_the_author_wrote
        text = "verify:\n  images: true\n  external_links: false\nlint:\n  style: polite\n"

        assert_equal [%w[verify images]], RetiredKeyRemover.authored(text, RETIRED)
      end

      def test_should_remove_only_the_retired_lines_and_keep_comments
        text = <<~YAML
          # 検査の設定
          verify:
            images: true # 画像パスの存在チェック
            bare_urls: true # 裸 URL の検出と警告
            external_links: false # 外部 URL

            # 以下は external_links: true のときだけ効きます
            timeout: 10
        YAML

        result = RetiredKeyRemover.remove(text, [%w[verify images], %w[verify bare_urls]])

        assert_equal <<~YAML, result
          # 検査の設定
          verify:
            external_links: false # 外部 URL

            # 以下は external_links: true のときだけ効きます
            timeout: 10
        YAML
      end

      def test_should_remove_the_nested_block_under_a_retired_key
        text = <<~YAML
          lint:
            config:
              rules:
                max-ten: 3
            style: polite
          book:
            main_title: 本
        YAML

        assert_equal <<~YAML, RetiredKeyRemover.remove(text, [%w[lint config]])
          lint:
            style: polite
          book:
            main_title: 本
        YAML
      end

      def test_should_remove_a_parent_left_without_keys
        text = <<~YAML
          spellcheck:
            # 除外する語
            extra_words:
              - foo

          book:
            main_title: 本
        YAML

        assert_equal <<~YAML, RetiredKeyRemover.remove(text, [%w[spellcheck extra_words]])

          book:
            main_title: 本
        YAML
      end

      def test_should_give_up_on_flow_style_mappings
        text = "verify: { images: true, external_links: false }\n"

        assert_nil RetiredKeyRemover.remove(text, [%w[verify images]])
      end

      def test_should_move_the_value_to_the_end_of_the_new_parent
        text = <<~YAML
          book:
            main_title: "本"
            isbn: "" # 任意

          output:
            targets: pdf

            # ------- 表紙・裏表紙設定 -------
            cover: light # 標準添付 light 表紙
            # cover: dark

            pdf:
              combined: true
        YAML

        assert_equal <<~YAML, RetiredKeyRemover.move(text, %w[output cover], %w[book cover])
          book:
            main_title: "本"
            isbn: "" # 任意
            cover: light # 標準添付 light 表紙

          output:
            targets: pdf

            # ------- 表紙・裏表紙設定 -------
            # cover: dark

            pdf:
              combined: true
        YAML
      end

      # 手で移した後など、移した先がすでにあれば、そちらを残して元の行だけを消す
      def test_should_keep_the_new_key_when_it_is_already_written
        text = "book:\n  cover: dark\noutput:\n  cover: master\n  targets: pdf\n"

        assert_equal "book:\n  cover: dark\noutput:\n  targets: pdf\n",
                     RetiredKeyRemover.move(text, %w[output cover], %w[book cover])
      end

      def test_should_give_up_moving_when_the_new_parent_is_missing
        assert_nil RetiredKeyRemover.move("output:\n  cover: master\n", %w[output cover], %w[book cover])
      end
    end
  end
end
