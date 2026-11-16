# frozen_string_literal: true

# ================================================================
# Test: guards/trait_combination_check_test.rb
# ================================================================
# テスト対象:
#   Guards::TraitCombinationCheck（lib/vivlio_starter/cli/guards/trait_combination_check.rb）
#
# 検証内容（v2-architecture-spec.md §2.5・§8 の S5 の決め 2・3・6）:
#   - 既定の本（横書き・リフロー）と、縦書きの本は違反 0 件
#   - 知らない book.type・page.writing_mode・page.layout は 🔴（書ける値を示す）
#   - page.layout: fixed は S9 まで 🔴（その間は、索引と用語集の 🟡 を重ねない）
#   - 設定が無い（プロジェクトの外）ときは何も出さない（ProjectRootCheck が示す）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class GuardsTraitCombinationCheckTest < Minitest::Test
      def test_should_pass_for_the_default_book
        assert_empty validate
      end

      # 縦書きは止めない。S5 で変わるのは綴じの向きと隠しノンブルの左右だけ
      def test_should_pass_for_a_vertical_book
        assert_empty validate(page: { writing_mode: 'vertical', layout: 'reflowable' })
      end

      def test_should_pass_for_a_novel_with_the_resolved_defaults
        assert_empty validate(book: { type: 'novel' }, page: { writing_mode: 'vertical', layout: 'reflowable' },
                              index_glossary: { enabled: false })
      end

      def test_should_report_an_unknown_book_type_with_the_valid_names
        violations = validate(book: { type: 'novle' })

        assert_equal 1, violations.size
        assert_predicate violations.first, :error?
        assert_includes violations.first.message, 'book.type'
        assert_includes violations.first.message, 'novle'
        assert_equal '書ける値: techbook・novel・picture_book', violations.first.detail
      end

      def test_should_report_unknown_axis_values_with_the_valid_values
        violations = validate(page: { writing_mode: 'tategaki', layout: 'fix' })

        assert_equal 2, violations.size
        assert(violations.all?(&:error?))
        assert_includes violations[0].message, 'page.writing_mode'
        assert_equal '書ける値: horizontal・vertical', violations[0].detail
        assert_includes violations[1].message, 'page.layout'
        assert_equal '書ける値: reflowable・fixed', violations[1].detail
      end

      def test_should_stop_a_fixed_layout_book_until_the_fixed_pipeline_exists
        violations = validate(page: { writing_mode: 'horizontal', layout: 'fixed' }, index_glossary: { enabled: false })

        assert_equal 1, violations.size
        assert_predicate violations.first, :error?
        assert_includes violations.first.message, 'page.layout: fixed'
        assert_includes violations.first.detail, 'reflowable'
      end

      # 固定レイアウトを 🔴 で止めている間は、索引の 🟡 を重ねない。S9 で 🔴 を外したら、
      # このテストを「🟡 が 1 件」に書き換える
      def test_should_not_add_the_index_warning_while_fixed_layout_is_stopped
        violations = validate(page: { writing_mode: 'horizontal', layout: 'fixed' }, index_glossary: { enabled: true })

        assert_equal %i[error], violations.map(&:severity)
      end

      def test_should_pass_without_a_configuration
        assert_empty Guards::TraitCombinationCheck.new(config: nil).validate
      end

      private

      BASE = { book: { type: 'techbook' }, page: { writing_mode: 'horizontal', layout: 'reflowable' },
               index_glossary: { enabled: true } }.freeze

      def validate(overrides = {})
        Guards::TraitCombinationCheck.new(config: Common.wrap_config(BASE.merge(overrides))).validate
      end
    end
  end
end
