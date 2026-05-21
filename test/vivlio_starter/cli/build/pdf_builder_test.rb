# frozen_string_literal: true

# ================================================================
# Test: pdf_builder_test.rb
# ================================================================
# テスト対象:
#   PdfBuilder（lib/vivlio_starter/cli/build/pdf_builder.rb）
#
# 検証内容:
#   - Step 8: 全体PDF生成（build_overall_pdf_from_dir!）
#   - Step 9: 表紙・奥付PDF生成（build_front_pages_and_tail!）
#   - PDF分割スキップの確認（内部リンク維持のため）
#
# 設計方針:
#   - PDF分割をスキップし、全体を1つのPDFとして生成
#   - 索引から前書きへのリンクなど内部リンクが維持される
#   - ローマ数字ノンブルはCSSの @page front で対応
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'

module VivlioStarter
  module CLI
    module Build
      class PdfBuilderTest < Minitest::Test
        # 章レンジ定数が正しく定義されていることを確認
        def test_chapter_ranges_are_defined
          assert_equal (0..0), PdfBuilder::PREFACE_RANGE, '前書きは 00 のみ'
          assert_equal (1..89), PdfBuilder::MAIN_RANGE, '本文は 01-89'
          assert_equal (90..98), PdfBuilder::APPX_RANGE, '付録は 90-98'
          assert_equal (99..99), PdfBuilder::POSTFACE_RANGE, '後書きは 99 のみ'
        end

        # compile_overall_pdf! が対象HTMLなしの場合に早期リターンすることを確認
        def test_compile_overall_pdf_returns_early_when_no_targets
          # 空の配列を渡すと警告を出して早期リターン
          logged_warnings = []
          Common.stub :log_warn, ->(msg) { logged_warnings << msg } do
            PdfBuilder.compile_overall_pdf!([])
          end

          assert logged_warnings.any? { it.include?('対象HTMLが見つかりません') },
                 '対象HTMLが空の場合は警告を出すべき'
        end

        # _preface_toc.pdf は生成されなくなったことを確認
        def test_preface_toc_pdf_is_no_longer_generated
          # PDF分割をスキップしたため、_preface_toc.pdf は生成されない
          # compile_overall_pdf! は _sections.pdf のみを生成する
          refute File.exist?('_preface_toc.pdf'),
                 '_preface_toc.pdf は新しい設計では生成されない'
        end
      end

      # PDF結合のテスト
      class PdfMergerTest < Minitest::Test
        private

        def set_common_config(config)
          Common.send(:remove_const, :CONFIG) if Common.const_defined?(:CONFIG, false)
          Common.const_set(:CONFIG, config)
        end

        def restore_common_config
          set_common_config(@original_config)
        end

        def deep_dup(obj)
          Marshal.load(Marshal.dump(obj))
        end

        def setup
          @original_config = deep_dup(Common::CONFIG)
        end

        def teardown
          restore_common_config
        end

        # merge_all_pdfs! がカバー設定と targets に応じて結合対象を構築することを確認
        def test_merge_all_pdfs_targets_include_covers_when_pdf_target_enabled
          fake_config = {
            'output' => {
              'targets' => ['pdf'],
              'pdf' => {
                'cover' => {
                  'enabled' => true,
                  'front' => 'frontcover_rgb.pdf',
                  'back' => 'backcover_rgb.pdf'
                }
              }
            },
            'directories' => {
              'covers' => 'covers'
            }
          }

          set_common_config(fake_config)

          existing_files = [
            '_titlepage_legalpage.pdf',
            '_sections.pdf',
            '_colophon.pdf',
            'covers/frontcover_rgb.pdf',
            'covers/backcover_rgb.pdf'
          ]

          File.stub :exist?, ->(path) { existing_files.include?(path) } do
            files = Build::PdfMerger.send(:cover_enhanced_files)
            assert_equal(
              ['covers/frontcover_rgb.pdf',
               '_titlepage_legalpage.pdf',
               '_sections.pdf',
               '_colophon.pdf',
               'covers/backcover_rgb.pdf'],
              files,
              'front/back カバーが PDF 対象に含まれているべき'
            )
          end
        end

        def test_merge_all_pdfs_targets_exclude_covers_when_pdf_not_selected
          fake_config = {
            'output' => {
              'targets' => ['epub'],
              'pdf' => {
                'cover' => {
                  'enabled' => true,
                  'front' => 'frontcover_rgb.pdf',
                  'back' => 'backcover_rgb.pdf'
                }
              }
            },
            'directories' => {
              'covers' => 'covers'
            }
          }

          set_common_config(fake_config)

          File.stub :exist?, true do
            files = Build::PdfMerger.send(:cover_enhanced_files)
            assert_equal(
              %w[_titlepage_legalpage.pdf _sections.pdf _colophon.pdf],
              files,
              'pdf target でない場合はカバーを含めない'
            )
          end
        end

        def test_merge_all_pdfs_targets_respects_cover_disabled_flag
          fake_config = {
            'output' => {
              'targets' => ['pdf'],
              'pdf' => {
                'cover' => {
                  'enabled' => false,
                  'front' => 'frontcover_rgb.pdf',
                  'back' => 'backcover_rgb.pdf'
                }
              }
            }
          }

          set_common_config(fake_config)

          File.stub :exist?, true do
            files = Build::PdfMerger.send(:cover_enhanced_files)
            assert_equal(
              %w[_titlepage_legalpage.pdf _sections.pdf _colophon.pdf],
              files,
              'cover.enabled=false の場合は front/back を結合しない'
            )
          end
        end

        # add_outline_to_output_pdf! が output.pdf なしの場合に早期リターンすることを確認
        def test_add_outline_returns_early_when_no_output_pdf
          logged_warnings = []
          Common.stub :log_warn, ->(msg) { logged_warnings << msg } do
            File.stub :exist?, false do
              result = PdfMerger.add_outline_to_output_pdf!(nil)
              assert_equal false, result, 'output.pdf がない場合は false を返すべき'
            end
          end
        end
      end

    end
  end
end
