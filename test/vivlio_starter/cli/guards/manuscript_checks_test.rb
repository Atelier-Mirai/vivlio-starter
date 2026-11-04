# frozen_string_literal: true

# ================================================================
# Test: guards/manuscript_checks_test.rb
# ================================================================
# テスト対象:
#   Guards.manuscript_checks と Guards::ManuscriptScope
#   （lib/vivlio_starter/cli/guards.rb・guards/manuscript_scope.rb）
#
# 検証内容:
#   - build と preflight が使う原稿の中身の検査が、4 つそろっている
#   - 調べる原稿を渡すと、その原稿だけを調べる（章を指定したビルドで、ほかの章の閉じ忘れで止めない）
#   - 渡さなければ contents/ の全原稿を調べる
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class ManuscriptChecksTest < Minitest::Test
      def test_should_list_the_four_manuscript_checks
        classes = Guards.manuscript_checks.map(&:class)

        assert_equal [Guards::CodeFenceCheck, Guards::StrayPageBreakCheck,
                      Guards::ContainerFenceCheck, Guards::ContainerClassCheck], classes
      end

      # 45 章の閉じ忘れは、12 章だけを調べるときには出さない。全原稿を調べるときは出す
      def test_should_check_only_the_given_chapters
        with_temp_project do
          File.write('contents/12-basics.md', "# 基本\n\n本文です。\n")
          File.write('contents/45-draft.md', "# 書きかけ\n\n:::{.memo}\n本文\n\n```ruby\nputs 1\n")

          scoped = Guards.manuscript_checks(['contents/12-basics.md']).flat_map(&:validate)
          whole = Guards.manuscript_checks.flat_map(&:validate)

          assert_empty scoped
          assert_equal 2, whole.count(&:error?), 'コードフェンスとコンテナの閉じ忘れ'
          assert(whole.all? { it.message.include?('contents/45-draft.md') })
        end
      end

      private

      def with_temp_project
        Dir.mktmpdir('vs-manuscript-checks') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            FileUtils.mkdir_p('contents')
            File.write('config/book.yml', "book:\n  main_title: 'test'\n")
            yield
          end
        end
      end
    end
  end
end
