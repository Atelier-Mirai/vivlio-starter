# frozen_string_literal: true

# ================================================================
# Test: build/gaiji_test.rb
# ================================================================
# 本の書体にない漢字（外字）を、字の形の図形にして PDF に組む（Gaiji・改善案 #127 段階 4）。
# 書体の並びは同梱の書体で作り、書体を探す所（font_faces）は差し替える——テストが
# 手元の PC に入っている書体で結果を変えないため。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process/glyph_coverage_check'
require 'vivlio_starter/cli/build/gaiji'

module VivlioStarter
  module CLI
    class GaijiTest < Minitest::Test
      Gaiji = Build::Gaiji
      FontMetrics = Build::FontMetrics
      FONTS = File.expand_path('../../../../stylesheets/fonts', __dir__)
      NOTO_SERIF = "#{FONTS}/Noto_Serif_JP/NotoSerifJP-Regular.ttf"

      # 「暅」の形（字面の枠の中ほどに置いた四角）。見出し用と本文用で中身を変えて見分ける
      SERIF_GLYPH = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -880 1000 1000"><path d="M100 -800L900 -800L900 40Z"/></svg>\n)
      SANS_GLYPH = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -870 1000 1000"><path d="M50 -50Z"/></svg>\n)

      def setup
        Gaiji.reset!
        @original = Common::CONFIG
      end

      def teardown
        Gaiji.reset!
        Common.install_configuration!(@original)
      end

      # 本文は明朝、見出しはゴシックの太字の形に替える。周りの字と、形の無い字（太字の「暅」）はそのまま
      def test_should_replace_gaiji_in_pdf_html_with_stored_shapes
        in_project do
          FileUtils.mkdir_p(Gaiji::PROJECT_DIR)
          File.write(File.join(Gaiji::PROJECT_DIR, 'u6685-serif.svg'), SERIF_GLYPH)
          File.write(File.join(Gaiji::PROJECT_DIR, 'u6685-sans-bold.svg'), SANS_GLYPH)
          File.write('pdf/12-a.html', "<html><body><h3>祖暅の原理</h3><p>祖暅は<strong>暅</strong>&amp;</p></body></html>\n")

          replaced = Gaiji.stub(:font_faces, []) { Gaiji.apply_to_dir!('pdf') }
          html = File.read('pdf/12-a.html')

          assert_equal 2, replaced
          assert_match(%r{<h3>祖<svg [^>]*viewBox="0 -870 1000 1000"[^>]*aria-label="暅"[^>]*>.*?</svg>の原理</h3>}, html)
          assert_match(%r{<p>祖<svg [^>]*viewBox="0 -880 1000 1000"[^>]*>.*?</svg>は<strong>暅</strong>&amp;</p>}, html)
          assert_includes html, 'fill:currentColor', '周りの字の色に従う'
        end
      end

      # 書体の並びにある字しか無い HTML は書き換えない
      def test_should_leave_html_without_gaiji_untouched
        in_project do
          original = "<html><body><p>漢字だけの本文</p></body></html>\n"
          File.write('pdf/11-a.html', original)

          assert_equal 0, Gaiji.stub(:font_faces, []) { Gaiji.apply_to_dir!('pdf') }
          assert_equal original, File.read('pdf/11-a.html')
        end
      end

      # 書体から取った形は .cache/ に置き、keep（build）のときだけ OFL の書体の形をプロジェクトにも置く。
      # 字の黒い部分の上下の中心を、字面の中心（INK_CENTER）にそろえる
      def test_should_extract_a_shape_and_keep_ofl_shapes_in_the_project_only_on_build
        in_project do
          face = Gaiji::Face.new(path: NOTO_SERIF, index: nil, name: 'Noto Serif JP', tier: 0, style: :serif, weight: 400)
          Gaiji.stub(:font_faces, [face]) do
            assert_equal 1, Gaiji.resolve([['永', :serif, false]]).size
            refute_path_exists File.join(Gaiji::PROJECT_DIR, 'u6c38-serif.svg'), 'preflight はプロジェクトに書かない'
            assert_path_exists File.join(Gaiji::CACHE_DIR, 'u6c38-serif.svg')

            Gaiji.resolve([['永', :serif, false]], keep: true)
          end

          svg = File.read(File.join(Gaiji::PROJECT_DIR, 'u6c38-serif.svg'))
          assert_includes svg, 'SIL Open Font License'
          top = svg[/viewBox="0 (-?[\d.]+) /, 1].to_f
          ink = svg[/d="([^"]+)"/, 1].scan(/-?\d+(?:\.\d+)?/).map(&:to_f).each_slice(2).map(&:last)
          assert_in_delta Gaiji::INK_CENTER - Gaiji::EM_TOP, ((ink.min + ink.max) / 2) - top, 1.0
        end
      end

      # 形の取れなかった字は覚え、書体の置き場が変わるまで探し直さない（preflight のたびに 5 秒かけない）
      def test_should_not_search_fonts_again_for_a_known_missing_character
        in_project do
          calls = 0
          Gaiji.stub(:font_faces, -> { calls += 1; [] }) do
            assert_empty Gaiji.resolve([['暅', :serif, false]])
            assert_empty Gaiji.resolve([['暅', :serif, false]])
          end

          assert_equal 1, calls
        end
      end

      # 形（明朝系かゴシック系か）が合う → OFL の書体 → 太さが近い
      def test_should_choose_the_matching_style_before_the_ofl_font
        face = ->(name, tier, style, weight) { Gaiji::Face.new(path: name, index: nil, name:, tier:, style:, weight:) }
        source_han = face.('Source Han Serif SemiBold', 0, :serif, 600)
        songti = face.('Songti SC Regular', 1, :serif, 400)
        hiragino = face.('Hiragino Sans GB W6', 1, :sans, 600)

        assert_equal source_han, Gaiji.best_face([songti, hiragino, source_han], :serif, false)
        assert_equal hiragino, Gaiji.best_face([songti, hiragino, source_han], :sans, true)
        assert_equal songti, Gaiji.best_face([songti, face.('Songti SC Black', 1, :serif, 900)], :serif, false)
      end

      # 付属の書体は、埋め込みの制限（fsType）が許すものだけ。埋め込み不可（2）とビットマップだけ（0x200）は使わない
      def test_should_use_only_embeddable_system_fonts
        assert Gaiji.embeddable?(0x0000)
        assert Gaiji.embeddable?(0x0008)
        refute Gaiji.embeddable?(0x0002)
        refute Gaiji.embeddable?(0x0208)
      end

      private

      # 本文は Noto Serif JP、見出しは Noto Sans JP の本。書体の並びは同梱の書体で作る
      def in_project
        Dir.mktmpdir('vs-gaiji') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('pdf')
            Common.install_configuration!(
              Common.build_direct_configuration(typography: { body: { font: 'Noto Serif JP' }, heading: { font: 'Noto Sans JP' } })
            )
            PreProcessCommands::GlyphCoverageCheck.stub(:font_chains, chains) { yield }
          end
        end
      end

      def chains
        hackgen = FontMetrics.load("#{FONTS}/hackgen35/HackGen35ConsoleNF-Regular.ttf")
        { body: [FontMetrics.load(NOTO_SERIF), hackgen],
          heading: [FontMetrics.load("#{FONTS}/Noto_Sans_JP/NotoSansJP-Bold.ttf"), hackgen], code: [hackgen] }
      end
    end
  end
end
