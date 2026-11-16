# frozen_string_literal: true

# ================================================================
# Test: book_traits_test.rb
# ================================================================
# テスト対象:
#   BookTraits（lib/vivlio_starter/cli/book_traits.rb）と Common.traits
#   （v2-architecture-spec.md §2.4）
#   - page.writing_mode・page.layout から軸の値を作る（知らない値・設定なしは既定）
#   - 連動して決まる値（綴じの向き・奇数ページの側・原稿の単位）
#   - Common.traits は、設定を差し替えるたびに作り直される
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    class BookTraitsTest < Minitest::Test
      def test_should_resolve_a_horizontal_reflowable_book_as_left_bound
        traits = resolve(writing_mode: 'horizontal', layout: 'reflowable')

        assert_equal BookTraits.new(writing_mode: :horizontal, layout: :reflowable), traits
        refute_predicate traits, :vertical?
        refute_predicate traits, :fixed?
        assert_equal :ltr, traits.binding
        assert_equal :right, traits.recto_side
        assert_equal :chapter, traits.unit
      end

      def test_should_derive_right_binding_from_vertical_writing
        traits = resolve(writing_mode: 'vertical', layout: 'reflowable')

        assert_predicate traits, :vertical?
        assert_equal :rtl, traits.binding
        assert_equal :left, traits.recto_side
        assert_equal :chapter, traits.unit, '原稿の単位は組方向で変わらない'
      end

      def test_should_derive_the_page_unit_from_fixed_layout
        traits = resolve(writing_mode: 'horizontal', layout: 'fixed')

        assert_predicate traits, :fixed?
        assert_equal :page, traits.unit
        assert_equal :ltr, traits.binding, '綴じの向きはレイアウトで変わらない'
      end

      # 知らない値は既定として組む。誤りは Guards::TraitCombinationCheck が示す
      def test_should_fall_back_to_the_defaults_for_unknown_or_missing_values
        default = BookTraits.new(writing_mode: :horizontal, layout: :reflowable)

        assert_equal default, resolve(writing_mode: 'tategaki', layout: 'fix')
        assert_equal default, resolve(writing_mode: nil, layout: nil)
        assert_equal default, BookTraits.resolve(Common.wrap_config({ book: { main_title: '題' } }))
        assert_equal default, BookTraits.resolve(nil), 'プロジェクトの外（CONFIG が nil）'
        assert_predicate resolve(writing_mode: ' Vertical ', layout: 'reflowable'), :vertical?
      end

      def test_should_rebuild_common_traits_when_the_configuration_is_replaced
        original = Common::CONFIG

        Common.install_configuration!(Common.wrap_config({ page: { writing_mode: 'vertical' } }))
        assert_equal :rtl, Common.traits.binding

        Common.install_configuration!(Common.wrap_config({ page: { writing_mode: 'horizontal' } }))
        assert_equal :ltr, Common.traits.binding
      ensure
        Common.install_configuration!(original)
      end

      private

      def resolve(writing_mode:, layout:) = BookTraits.resolve(Common.wrap_config({ page: { writing_mode:, layout: } }))
    end
  end
end
