# frozen_string_literal: true

# ================================================================
# Test: page_layout_test.rb
# ================================================================
# テスト対象:
#   - vivliostyle size 解決（resolve_vivliostyle_size）
#   - CSS break-before: recto による右ページ始まり
#   - 奥付の偶数ページ配置（空白ページ挿入）
#   - 画像オーバーフロー防止 CSS
#
# 設計方針:
#   - PDF を実際にビルドせずにロジックを検証
#   - CSS ファイルの内容チェックで break-before を確認
#   - insert_blank_page_before_colophon のロジックをユニットテスト
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/vivliostyle'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/pre_process/css_updater'

module VivlioStarter
  module CLI
    # ================================================================
    # vivliostyle.config.js size プロパティのテスト
    # ================================================================
    class VivliostyleConfigSizeTest < Minitest::Test
      def test_resolve_vivliostyle_size_returns_a5_for_a5_preset
        config = Common.wrap_config(page: { size: 'A5' })
        size = VivliostyleCommands.resolve_vivliostyle_size(config)
        assert_equal 'A5', size
      end

      def test_resolve_vivliostyle_size_returns_a5_when_page_nil
        size = VivliostyleCommands.resolve_vivliostyle_size(Common.wrap_config(page: nil))
        assert_equal 'A5', size
      end

      def test_resolve_vivliostyle_size_returns_dimensions_when_no_size_key
        config = Common.wrap_config(page: { width: '182mm', height: '257mm' })
        size = VivliostyleCommands.resolve_vivliostyle_size(config)
        assert_equal '182mm 257mm', size
      end

      def test_resolve_vivliostyle_size_returns_b5_for_b5_preset
        config = Common.wrap_config(page: { size: 'B5' })
        size = VivliostyleCommands.resolve_vivliostyle_size(config)
        assert_equal 'B5', size
      end

      def test_resolve_vivliostyle_size_normalizes_case
        config = Common.wrap_config(page: { size: 'a4' })
        size = VivliostyleCommands.resolve_vivliostyle_size(config)
        assert_equal 'A4', size
      end

      # 注: ルート vivliostyle.config.js の size 検証は手動フロー撤去
      # （vivlioverso-manual-flow-removal-spec.md）に伴い削除。生成 config の
      # size は vivliostyle_config_writer_test.rb が検証する。
    end

    # ================================================================
    # CSS break-before: recto のテスト
    # ================================================================
    class CssBreakBeforeTest < Minitest::Test
      STYLESHEETS_DIR = 'stylesheets'

      def test_toc_css_has_break_before_recto
        css = read_css('toc.css')
        assert_match(/break-before:\s*recto/, css,
                     'toc.css に break-before: recto が含まれていること')
      end

      def test_chapter_common_css_has_break_before_recto
        css = read_css('chapter-common.css')
        assert_match(/break-before:\s*recto/, css,
                     'chapter-common.css に break-before: recto が含まれていること')
      end

      def test_glossary_css_has_break_before_recto
        css = read_css('glossary.css')
        assert_match(/break-before:\s*recto/, css,
                     'glossary.css に break-before: recto が含まれていること')
      end

      def test_index_css_has_break_before_recto
        css = read_css('index.css')
        assert_match(/break-before:\s*recto/, css,
                     'index.css に break-before: recto が含まれていること')
      end

      def test_postface_css_has_break_before_recto
        css = read_css('postface.css')
        assert_match(/break-before:\s*recto/, css,
                     'postface.css に break-before: recto が含まれていること')
      end

      # 前付・奥付は本文スパインの末尾に相乗りするため、単独ドキュメントだった頃に
      # @page :nth(1) が消していた柱を、名前付きページ側で明示的に消す必要がある。
      # 消し忘れると直前の章のタイトルが string() に残ったまま出る。
      def test_front_and_back_matter_named_pages_suppress_running_head
        { 'titlepage.css' => 'titlepage', 'legalpage.css' => 'legalpage',
          'colophon.css' => 'colophon' }.each do |file, page_name|
          block = named_page_block(read_css(file), page_name)

          assert_match(/@top-right\s*\{\s*content:\s*none;?\s*\}/m, block,
                       "#{file} の @page #{page_name} が柱を消していること")
        end
      end

      # ノド／小口は @page :left / :right が表裏で入れ替える。相乗りすると本文の
      # ページ数次第で表裏が変わるため、名前付きページ側で綴じ側を固定する。
      # 本扉＝右ページ（ノドが左）、権利ページと奥付＝左ページ（ノドが右）。
      def test_front_and_back_matter_named_pages_pin_the_gutter
        title = named_page_block(read_css('titlepage.css'), 'titlepage')

        assert_match(/margin-left:\s*var\(--page-margin-inner\)/, title, '本扉のノドは左であること')
        assert_match(/margin-right:\s*var\(--page-margin-outer\)/, title, '本扉の小口は右であること')

        { 'legalpage.css' => 'legalpage', 'colophon.css' => 'colophon' }.each do |file, page_name|
          block = named_page_block(read_css(file), page_name)

          assert_match(/margin-left:\s*var\(--page-margin-outer\)/, block, "#{file} の小口は左であること")
          assert_match(/margin-right:\s*var\(--page-margin-inner\)/, block, "#{file} のノドは右であること")
        end
      end

      # 生成 CSS（book-settings.css）は page.chapter_pagebreak: verso のとき裸の body へ
      # break-before: verso を出す。打ち消さないと前付・奥付の前に白紙が挟まり、
      # 結合時の切り出し位置がずれる。
      def test_front_and_back_matter_cancel_the_generated_pagebreak
        { 'titlepage.css' => 'titlepage', 'legalpage.css' => 'legalpage',
          'colophon.css' => 'colophon' }.each do |file, klass|
          css = read_css(file)

          assert_match(/body\.#{klass}\s*\{[^}]*break-before:\s*auto/m, css,
                       "#{file} が body.#{klass} で break-before を打ち消していること")
        end
      end

      private

      def read_css(filename)
        File.read(File.join(STYLESHEETS_DIR, filename), encoding: 'utf-8')
      end

      # `@page <name> { ... }` の中身を取り出す。マージンボックスの入れ子があるため
      # 素朴な `[^}]*` では途中で切れる。深さを数えて閉じ括弧まで読む。
      def named_page_block(css, page_name)
        start = css.index(/@page\s+#{page_name}\s*\{/) or return ''

        depth = 0
        css[start..].each_char.with_index do |ch, i|
          depth += 1 if ch == '{'
          next unless ch == '}'

          depth -= 1
          return css[start, i + 1] if depth.zero?
        end
        ''
      end
    end

    # ================================================================
    # 画像オーバーフロー防止 CSS のテスト
    # ================================================================
    class CssImageOverflowTest < Minitest::Test
      def test_base_css_has_image_max_inline_size
        css = File.read('stylesheets/base.css', encoding: 'utf-8')
        assert_match(/img\s*\{[^}]*max-inline-size:\s*100%/m, css,
                     'base.css に img { max-inline-size: 100% } が含まれていること')
      end
    end

    # ================================================================
    # 奥付偶数ページ配置ロジックのテスト
    # ================================================================
    class ColophonPageParityTest < Minitest::Test
      def setup
        @merger = VivlioStarter::CLI::Build::PdfMerger
      end

      # 検証したいのは parity 判定だけなので、改丁設定は「面を問わない（any）」以外に
      # 固定する。固定しないと config/book.yml の chapter_pagebreak 次第で
      # 早期 return に入り、判定を素通りしたまま緑になる。
      def with_paged_colophon(&) = @merger.stub(:chapter_pagebreak_any?, false, &)

      def segment(role, path, pages)
        VivlioStarter::CLI::Build::PdfMerger::Segment.new(role:, path:, range: '1-z', pages:)
      end

      def test_insert_blank_when_body_pages_even
        # カバー除外後の本文ページ数が偶数 → 空白ページ挿入が必要
        # covers/ は除外、前付=2, 本文=8 → total=10(偶数)
        segments = [
          segment(:cover_front,  'covers/front.pdf',           1),
          segment(:front_matter, '_titlepage_legalpage.pdf',   2),
          segment(:body,         '_sections.pdf',              8),
          segment(:colophon,     '_colophon.pdf',              1)
        ]

        with_paged_colophon do
          VivlioStarter::CLI::Build::Utilities.stub(:ensure_blank_page_pdf, '_blank_before_colophon.pdf') do
            result = @merger.send(:insert_blank_page_before_colophon, segments)
            roles = result.map(&:role)

            assert_includes roles, :blank, '偶数ページ数のとき空白ページが挿入されること'
            assert roles.index(:blank) < roles.index(:colophon), '空白ページは奥付の前に配置されること'
          end
        end
      end

      def test_no_blank_when_body_pages_odd
        # カバー除外後の本文ページ数が奇数 → 空白ページ不要
        # covers/ は除外、前付=2, 本文=9 → total=11(奇数)
        segments = [
          segment(:cover_front,  'covers/front.pdf',           1),
          segment(:front_matter, '_titlepage_legalpage.pdf',   2),
          segment(:body,         '_sections.pdf',              9),
          segment(:colophon,     '_colophon.pdf',              1)
        ]

        with_paged_colophon do
          result = @merger.send(:insert_blank_page_before_colophon, segments)

          refute_includes result.map(&:role), :blank, '奇数ページ数のとき空白ページは挿入されないこと'
        end
      end

      def test_cover_excluded_from_parity
        # カバー(1p)を含めると偶数(12)だが、除外すると奇数(11) → 挿入なし
        segments = [
          segment(:cover_front,  'covers/frontcover_rgb.pdf',  1),
          segment(:front_matter, '_titlepage_legalpage.pdf',   2),
          segment(:body,         '_sections.pdf',              9),
          segment(:colophon,     '_colophon.pdf',              1)
        ]

        with_paged_colophon do
          result = @merger.send(:insert_blank_page_before_colophon, segments)

          refute_includes result.map(&:role), :blank, 'カバーを除外した本文ページ数が奇数なら空白挿入なし'
        end
      end

      def test_no_colophon_in_files_returns_unchanged
        segments = [
          segment(:front_matter, '_titlepage_legalpage.pdf', 2),
          segment(:body,         '_sections.pdf',            9)
        ]

        with_paged_colophon do
          assert_equal segments, @merger.send(:insert_blank_page_before_colophon, segments),
                       '奥付がない場合は区間列が変更されないこと'
        end
      end

      def test_zero_page_count_returns_unchanged
        segments = [
          segment(:front_matter, '_titlepage_legalpage.pdf', 0),
          segment(:body,         '_sections.pdf',            0),
          segment(:colophon,     '_colophon.pdf',            0)
        ]

        with_paged_colophon do
          result = @merger.send(:insert_blank_page_before_colophon, segments)

          refute_includes result.map(&:role), :blank, 'ページ数 0 のとき空白ページは挿入されないこと'
        end
      end

      # 前付・奥付が本文 PDF に相乗りしていると 3 区間すべてが同じファイルを指す。
      # parity 判定がパスの綴りでなく role を見ていることを固定する。
      def test_parity_uses_role_not_path_when_matter_is_embedded
        sections = '_sections.pdf'
        segments = [
          segment(:front_matter, sections, 2),
          segment(:body,         sections, 8),
          segment(:colophon,     sections, 1)
        ]

        with_paged_colophon do
          VivlioStarter::CLI::Build::Utilities.stub(:ensure_blank_page_pdf, '_blank_before_colophon.pdf') do
            result = @merger.send(:insert_blank_page_before_colophon, segments)

            assert_includes result.map(&:role), :blank,
                            '同一ファイルの 3 区間でも前方 10 ページを数えて空白を挿入できること'
          end
        end
      end
    end

    # vivliostyle.config.js の size/title 同期テストは P3-4 で全文生成
    # （Build::VivliostyleConfigWriter）へ移行したため撤去した。
    # 生成の検証は test/vivlio_starter/cli/build/vivliostyle_config_writer_test.rb を参照。

    # ================================================================
    # calculate_align_max_width のテスト
    #
    # Vivliostyle が `min(26em, max-content)` を未対応なため、
    # CSS カスタムプロパティ `--align-max-width` として判型別に値を供給する。
    # 詳細は vivliostyle_warnings_spec.md 参照。
    # ================================================================
    class CalculateAlignMaxWidthTest < Minitest::Test
      CssUpdater = VivlioStarter::CLI::PreProcessCommands::CssUpdater

      def test_a5_returns_26em
        assert_equal '26em', CssUpdater.calculate_align_max_width('148mm')
      end

      def test_b5_jis_returns_36em
        assert_equal '36em', CssUpdater.calculate_align_max_width('182mm')
      end

      def test_b5_iso_returns_36em
        assert_equal '36em', CssUpdater.calculate_align_max_width('176mm')
      end

      def test_a4_returns_40em
        assert_equal '40em', CssUpdater.calculate_align_max_width('210mm')
      end

      def test_larger_than_a4_returns_40em
        assert_equal '40em', CssUpdater.calculate_align_max_width('257mm')
      end

      def test_invalid_value_falls_back_to_40em
        assert_equal '40em', CssUpdater.calculate_align_max_width('')
        assert_equal '40em', CssUpdater.calculate_align_max_width(nil)
      end

      def test_a5_boundary_155mm_returns_26em
        assert_equal '26em', CssUpdater.calculate_align_max_width('155mm')
      end

      def test_just_over_a5_boundary_returns_36em
        assert_equal '36em', CssUpdater.calculate_align_max_width('160mm')
      end
    end
  end
end
