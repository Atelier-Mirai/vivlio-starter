# frozen_string_literal: true

# ================================================================
# Test: build/output_target_test.rb
# ================================================================
# テスト対象:
#   Build::OutputTarget と四つの出力先の宣言（v2-architecture-spec.md §4.1・§4.2）
#   - 宣言が登録されていて、名前で引ける
#   - EPUB と Kindle の変換の並び（Kindle は EPUB の並びの後ろに Kindle だけの段を足す）
#   - body_classes が、並びの中の MarkBody の段が付けるクラスと一致する
#   - 変換の段は call(html_files, ctx)、本全体の段は call(book, ctx) を持つ
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/build/targets/pdf'
require 'vivlio_starter/cli/build/targets/print_pdf'
require 'vivlio_starter/cli/build/epub_flow'

module VivlioStarter
  module CLI
    class OutputTargetTest < Minitest::Test
      def test_should_find_each_declared_target_by_id
        %i[pdf print_pdf epub kindle].each { assert_equal it, Build::OutputTarget.for(it).id }

        error = assert_raises(ArgumentError) { Build::OutputTarget.for(:web) }
        assert_includes error.message, ':web'
      end

      def test_should_keep_pdf_targets_free_of_transforms
        %i[pdf print_pdf].each do |id|
          target = Build::OutputTarget.for(id)

          assert_equal :pdf, target.branch
          assert_equal :layered, target.css_form
          assert_empty target.transforms
          assert_empty target.finalizers
          assert_empty target.body_classes
        end
      end

      def test_should_append_kindle_transforms_after_the_shared_ones
        epub = Build::OutputTarget.for(:epub)
        kindle = Build::OutputTarget.for(:kindle)

        assert_equal 10, epub.transforms.size
        assert_equal 27, kindle.transforms.size
        assert_equal epub.transforms, kindle.transforms.first(10), 'Kindle は EPUB と同じ段から始まる'
        assert_equal Build::Transforms::Shared::MarkBody, epub.transforms.first
        assert_equal Build::Transforms::Shared::PostProcessIndexGlossary, epub.transforms.last,
                     '索引・用語集の書き換えは、id を消しうる段の後（両方で走る段の最後）'
        assert(kindle.transforms.last(17).all? { it.name.include?('::Transforms::Kindle::') })
      end

      def test_should_declare_css_form_assets_and_packager_per_target
        epub = Build::OutputTarget.for(:epub)
        kindle = Build::OutputTarget.for(:kindle)

        assert_equal %i[flat flat_literal], [epub.css_form, kindle.css_form]
        assert_equal %i[webp jpeg_png], [epub.assets.images, kindle.assets.images]
        assert_equal [true, false], [epub.assets.svg, kindle.assets.svg]
        assert_equal %i[vivliostyle_epub vivliostyle_epub_to_kpf], [epub.packager, kindle.packager]
        assert_equal [Common::BUILD_EPUB_DIR, Common::BUILD_KINDLE_DIR], [epub.workspace, kindle.workspace]
      end

      def test_should_run_author_priority_before_variant_fonts_and_report_last
        assert_equal [Build::Finalizers::AuthorPriority, Build::Finalizers::InversionReport],
                     Build::OutputTarget.for(:epub).finalizers
        assert_equal [Build::Finalizers::AuthorPriority, Build::Finalizers::VariantGlyphFonts,
                      Build::Finalizers::InversionReport],
                     Build::OutputTarget.for(:kindle).finalizers
      end

      def test_should_list_the_body_classes_that_mark_body_transforms_add
        %i[epub kindle].each do |id|
          target = Build::OutputTarget.for(id)
          marked = target.transforms.select { it.const_defined?(:BODY_CLASS, false) }.map { it::BODY_CLASS }

          assert_equal target.body_classes, marked
        end
        assert_equal %w[vs-epub vs-kindle], Build::OutputTarget.for(:kindle).body_classes
      end

      def test_should_give_every_step_a_two_argument_call
        %i[epub kindle].each do |id|
          target = Build::OutputTarget.for(id)

          [*target.transforms, *target.finalizers].each do |step|
            assert_equal 2, step.method(:call).arity, "#{step.name}.call は 2 引数"
          end
        end
      end
    end
  end
end
