# frozen_string_literal: true

# ================================================================
# Test: book_key_inserter_test.rb
# ================================================================
# テスト対象:
#   BookKeyInserter（lib/vivlio_starter/cli/book_key_inserter.rb）
#
# 検証内容（scaffold-update-notice-spec.md §10）:
#   - 雛形の並びのとおりに、コメントごと差し込む
#   - 著者の行には 1 行も触れない
#   - 差し込めないキーは、書き換えずに返す
#   - 実物の雛形の全キーを、消して差し込み直すと元に戻る
# ================================================================

require 'test_helper'
require 'date'
require 'yaml'
require 'vivlio_starter/cli/samovar'

module VivlioStarter
  module CLI
    class BookKeyInserterTest < Minitest::Test
      SCAFFOLD = <<~YAML
        # ======= 書籍情報 =======
        book:
          main_title: "{{MAIN_TITLE}}"
          cover: master # 表紙

        # ======= テーマ =======
        theme:
          color: blue # テーマの色

          # 章リードの大きさ
          lead_size: 1.2 # 本文に対する倍率
                         # 1.0〜2.0

          name: sakura # 絵の名前

        # ======= 索引設定 =======
        index:
          title: "索引"
      YAML

      def insert(text, keys, scaffold: SCAFFOLD) = BookKeyInserter.insert(text, scaffold, keys)

      def test_should_insert_after_the_previous_key_with_its_comments
        book = <<~YAML
          book:
            main_title: "わたしの本" # 著者のコメント

          theme:
            color: red # 赤にした

            name: ume
        YAML

        result = insert(book, %w[theme.lead_size])

        assert_equal <<~YAML, result.text
          book:
            main_title: "わたしの本" # 著者のコメント

          theme:
            color: red # 赤にした

            # 章リードの大きさ
            lead_size: 1.2 # 本文に対する倍率
                           # 1.0〜2.0

            name: ume
        YAML
        assert_equal %w[theme.lead_size], result.added
        assert_empty result.skipped
      end

      def test_should_put_the_first_child_right_below_its_parent
        result = insert("book:\n  cover: light\n", %w[book.main_title])

        assert_equal "book:\n  main_title: \"\"\n  cover: light\n", result.text, 'vs new の印は空にする'
      end

      # `# use: …` のように残した別の値は、前のキーから引き離さない
      def test_should_keep_commented_alternatives_with_their_key
        book = "theme:\n  color: red\n  # color: blue\n  # color: green\n\n  name: ume\n"

        result = insert(book, %w[theme.lead_size])

        assert_includes result.text, "  color: red\n  # color: blue\n  # color: green\n\n  # 章リードの大きさ\n"
      end

      # 次のキーのすぐ上のコメントは、そのキーの説明なので引き離さない
      def test_should_not_separate_a_comment_from_the_key_below_it
        book = "theme:\n  color: red\n  # 飾りの絵\n  name: ume\n"

        result = insert(book, %w[theme.lead_size])

        assert_includes result.text, "  # 飾りの絵\n  name: ume\n"
        assert_operator result.text.index('lead_size'), :<, result.text.index('# 飾りの絵')
      end

      def test_should_insert_a_new_section_with_its_heading
        book = "book:\n  cover: light\n\ntheme:\n  color: red\n"

        result = insert(book, %w[index])

        assert result.text.end_with?("  color: red\n\n# ======= 索引設定 =======\nindex:\n  title: \"索引\"\n"), result.text
      end

      def test_should_follow_the_indent_of_the_book
        book = "theme:\n    color: red\n"

        result = insert(book, %w[theme.lead_size])

        assert_includes result.text, "\n    # 章リードの大きさ\n    lead_size: 1.2 # 本文に対する倍率\n"
        assert_equal 1.2, YAML.safe_load(result.text).dig('theme', 'lead_size')
      end

      def test_should_insert_several_keys_in_order
        book = "book:\n  cover: light\n\ntheme:\n  color: red\n"

        result = insert(book, %w[theme.lead_size theme.name index])

        assert_equal %w[theme.lead_size theme.name index], result.added
        assert_equal %w[color lead_size name], YAML.safe_load(result.text)['theme'].keys
      end

      def test_should_add_a_missing_newline_at_the_end
        result = insert('book:', %w[theme]) # 親の book に値が無くても壊さない

        assert YAML.safe_load(result.text).key?('theme')
      end

      # 1 行にまとめた親の下には行を足せない。壊さずに返す
      def test_should_skip_a_key_under_a_flow_mapping
        book = "theme: { color: red }\n"

        result = insert(book, %w[theme.lead_size])

        assert_equal book, result.text
        assert_equal %w[theme.lead_size], result.skipped
        assert_empty result.added
      end

      def test_should_skip_a_key_whose_parent_is_gone
        book = "book:\n  cover: light\n"

        result = insert(book, %w[theme.lead_size])

        assert_equal book, result.text
        assert_equal %w[theme.lead_size], result.skipped
      end

      def test_should_add_the_keys_it_can_and_skip_the_others
        book = "book:\n  cover: light\n\ntheme: { color: red }\n"

        result = insert(book, %w[book.main_title theme.lead_size])

        assert_equal %w[book.main_title], result.added
        assert_equal %w[theme.lead_size], result.skipped
      end

      def test_should_leave_a_book_that_cannot_be_read
        book = "theme: [\n"

        result = insert(book, %w[theme.lead_size])

        assert_equal book, result.text
        assert_equal %w[theme.lead_size], result.skipped
      end

      # 配る雛形のどのキーでも、消して差し込み直すと同じ設定に戻る
      def test_every_key_of_the_real_scaffold_can_be_put_back
        scaffold = File.read(File.join(NewCommands::SCAFFOLD_SOURCE, 'config/book.yml'), encoding: 'utf-8')
        blank = scaffold.gsub(/\{\{[A-Z_]+\}\}/, '')
        settings = YAML.safe_load(blank, permitted_classes: [Date, Time], aliases: true)
        tried = 0

        all_keys = ScaffoldLock.book_keys(blank)
        all_keys.each do |key|
          book = RetiredKeyRemover.remove(blank, [key.split('.')]) or next

          # 消すと空になった親も一緒に消えるので、vs upgrade と同じく親から足す
          missing = all_keys - ScaffoldLock.book_keys(book)
          missing = missing.reject { missing.include?(it.rpartition('.').first) }
          result = BookKeyInserter.insert(book, scaffold, missing)
          tried += 1

          assert_equal missing, result.added, key
          assert_equal settings, YAML.safe_load(result.text, permitted_classes: [Date, Time], aliases: true), key
        end
        assert_operator tried, :>, 100, 'ほとんどのキーを確かめた'
      end
    end
  end
end
