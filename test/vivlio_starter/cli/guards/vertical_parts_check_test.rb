# frozen_string_literal: true

# ================================================================
# Test: guards/vertical_parts_check_test.rb
# ================================================================
# テスト対象:
#   Guards::VerticalPartsCheck（縦書きの本で使えない部品の 🟡。novel-vertical-spec.md §3.4）
#   Build::TextGridNotice（縦書きの本の版面の字数と行数の 💡。同 §4.2）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'
require 'vivlio_starter/cli/build/text_grid_notice'

module VivlioStarter
  module CLI
    class VerticalPartsCheckTest < Minitest::Test
      MANUSCRIPT = <<~MD
        # 章

        ::::{.side-by-side}
        左
        ::::

        :::{.book-card}
        ![](x.webp)
        :::

        ```markdown
        :::{.rotate-table}
        :::
        ```

        :::{.talk}
        :::
      MD

      def test_should_point_at_unsupported_parts_in_a_vertical_book
        violations = check(MANUSCRIPT, writing_mode: 'vertical')

        assert_equal %i[warn warn], violations.map(&:severity)
        assert_equal ['contents/11-sample.md:3 - 縦書きの本では左右に並べる記法（:::{.side-by-side}）を使えません',
                      'contents/11-sample.md:7 - 縦書きの本では本の紹介のカード（:::{.book-card}）を使えません'],
                     violations.map(&:message), 'コードの中の記法と、縦書きで読める会話は示さない'
      end

      def test_should_say_nothing_in_a_horizontal_book
        assert_empty check(MANUSCRIPT, writing_mode: 'horizontal')
      end

      # 字数が整数のときは数だけ、端数が 0.2 字以上なら天地の余白の直し方を添える
      def test_should_report_the_text_grid_of_a_vertical_book
        page = { size: 'BUNKO', base_font_size: '9pt', base_line_height: '14.85pt',
                 margin_top: '15mm', margin_bottom: '12.35mm', margin_inner: '13mm', margin_outer: '10mm' }
        grid = Build::TextGridNotice.resolve(page)

        assert_equal '版面: 38 字 × 16 行', Build::TextGridNotice.message(grid)

        uneven = Build::TextGridNotice.resolve(page.merge(margin_bottom: '11mm'))
        assert_match(/\A版面: 38\.4 字 × 16 行（天と地の余白の和を 1\.4mm 増やすと 38 字、1\.8mm 減らすと 39 字ちょうどになります）\z/,
                     Build::TextGridNotice.message(uneven))
      end

      private

      def check(markdown, writing_mode:)
        original = Common::CONFIG
        Dir.mktmpdir('vs-vertical-parts') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('contents')
            File.write('contents/11-sample.md', markdown)
            Common.install_configuration!(Common.wrap_config({ page: { writing_mode: } }))
            return Guards::VerticalPartsCheck.new.validate
          end
        end
      ensure
        Common.install_configuration!(original)
      end
    end
  end
end
