# frozen_string_literal: true

# ================================================================
# Test: build/derived_svg_test.rb
# ================================================================
# テスト対象:
#   DerivedSvg（著者の SVG 図版へ、PDF 用に書体を抱かせた複製を作る）
#
# 背景:
#   `<img>` 参照の SVG は独立文書で、本文 HTML の @font-face が届かない。
#   showcase / mermaid の生成 SVG は 2026-08-07 に塞いだが、著者が `images/` へ
#   置いた図版は素通りのままだった。実測（2026-09-10・本書 22 章の単章ビルド）で、
#   `font-family: sans-serif` の図 1 枚から `HiraKakuProN-W3` の Type 3 が 17 件出た。
#
# 検証方法:
#   書体の**解決**（どのスタックをどの書体へ寄せるか）は実フォントを要らない——
#   `face_paths` は実ファイルの有無しか見ないので、tmpdir に空の .ttf を置けば足りる。
#   サブセットの生成まで通す 1 本だけ、同梱の実フォントを持ち込む。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'
require 'vivlio_starter/cli/build/derived_svg'

module VivlioStarter
  module CLI
    class DerivedSvgTest < Minitest::Test
      DerivedSvg = Build::DerivedSvg

      # 同梱書体の実体。サブセットまで通す 1 本だけが使う。
      REAL_FONT = File.expand_path('../../../../stylesheets/fonts/Zen_Kaku_Gothic_New/ZenKakuGothicNew-Regular.ttf',
                                   __dir__)

      # 汎用名しか書いていない図は、書籍の見出し書体をスタックの先頭へ足す。
      # ここが効かないと、独立文書では何も解決できず OS フォント（Type 3）へ落ちる。
      def test_should_prepend_the_book_font_when_the_figure_names_only_a_generic_family
        with_project do
          svg = <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg"><style>
              .coord { font-family: sans-serif; font-size: 13px; }
            </style><text class="coord">座標</text></svg>
          SVG

          rewritten, families = DerivedSvg.resolve_families(svg)

          assert_includes rewritten, 'font-family: Zen Kaku Gothic New, sans-serif'
          assert_equal ['Zen Kaku Gothic New'], families
        end
      end

      # 著者が名指しした書体が手元にあるなら並べ替えない。意図した書体で組むのが正しい。
      def test_should_keep_the_authors_font_when_it_resolves
        with_project do
          svg = %(<svg xmlns="http://www.w3.org/2000/svg"><text font-family="'Zen Old Mincho', serif">春</text></svg>)

          rewritten, families = DerivedSvg.resolve_families(svg)

          assert_equal svg, rewritten, '解決できる指定は書き換えない'
          assert_equal ['Zen Old Mincho'], families
        end
      end

      # 汎用名は役割ごとに寄せ先を変える。明朝の図に見出しゴシックを当てると、
      # そこだけ周りの紙面と書体が違って見える。
      def test_should_map_generic_families_to_the_matching_book_font
        with_project do
          assert_equal 'Zen Old Mincho', DerivedSvg.book_font_for(%w[serif])
          assert_equal 'HackGen35 Console NF', DerivedSvg.book_font_for(%w[monospace])
          assert_equal 'Zen Kaku Gothic New', DerivedSvg.book_font_for(%w[sans-serif])
          # ui- 接頭辞も同じ扱い。判断がつかないものは見出し書体へ倒す。
          assert_equal 'Zen Old Mincho', DerivedSvg.book_font_for(%w[ui-serif])
          assert_equal 'Zen Kaku Gothic New', DerivedSvg.book_font_for(%w[cursive])
        end
      end

      # font-family は 3 か所に現れ、値の区切り方が違う（CSS は `;`、属性は引用符）。
      # どれか 1 つでも取りこぼすと、その字だけ Type 3 で残る。
      def test_should_rewrite_font_family_in_every_place_it_can_appear
        with_project do
          svg = <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg">
            <style>text { font-family: sans-serif; }</style>
            <text style="font-family: monospace">1000</text>
            <text font-family="serif">春</text>
            </svg>
          SVG

          rewritten, families = DerivedSvg.resolve_families(svg)

          assert_includes rewritten, 'font-family: Zen Kaku Gothic New, sans-serif;'
          assert_includes rewritten, %(style="font-family: HackGen35 Console NF, monospace")
          assert_includes rewritten, %(font-family="Zen Old Mincho, serif")
          assert_equal ['Zen Kaku Gothic New', 'HackGen35 Console NF', 'Zen Old Mincho'], families
        end
      end

      # 文字を持たない図（純粋な図形）は素材のまま運ぶ。複製すればステージングが太るだけ。
      def test_should_skip_a_figure_without_text
        with_project do
          source = write_svg('shapes.svg', %(<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>))

          assert_nil DerivedSvg.prepare(source)
        end
      end

      # 生成 SVG（showcase / mermaid）は既に自分で書体を抱えている。二重に埋めない。
      def test_should_skip_a_figure_that_already_embeds_a_font
        with_project do
          svg = %(<svg xmlns="http://www.w3.org/2000/svg"><style>@font-face{src:url("data:font/ttf;base64,AAA")}</style><text>春</text></svg>)
          source = write_svg('generated.svg', svg)

          assert_nil DerivedSvg.prepare(source)
        end
      end

      # ルートの <svg> が font-family を持つ図には既定を置かない。注入するのは CSS 規則で、
      # プレゼンテーション属性より強いため、著者がルートに書いた指定を上書きしてしまう。
      def test_should_not_force_a_default_family_over_the_root_attribute
        with_project do
          assert_equal 'Zen Kaku Gothic New', DerivedSvg.default_family(%(<svg xmlns="x"><text>春</text></svg>))
          assert_nil DerivedSvg.default_family(%(<svg xmlns="x" font-family="serif"><text>春</text></svg>))
        end
      end

      # 通しで 1 本。サブセットを抱いた複製が .cache/ にでき、**素材は 1 バイトも動かない**。
      def test_should_embed_a_subset_into_a_copy_and_leave_the_source_untouched
        skip '同梱書体が無い環境では検証できない' unless File.file?(REAL_FONT)

        with_project(real_font: true) do
          original = <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 40">
            <text font-family="sans-serif">座標</text></svg>
          SVG
          source = write_svg('coords.svg', original)

          derived = DerivedSvg.prepare(source)

          refute_nil derived, '派生が作られていない'
          assert_equal original, File.read(source), '素材が書き換えられている'

          embedded = File.read(derived)

          assert_includes embedded, '@font-face'
          assert_includes embedded, 'data:font/ttf;base64,'
          assert_includes embedded, 'font-synthesis-weight:none'
          assert_includes embedded, 'Zen Kaku Gothic New, sans-serif'
          # サブセットなので、和文フォント丸ごと（2〜4MB）と違い実質太らない
          assert_operator File.size(derived), :<, 200_000
        end
      end

      # 書体の設定を変えたら作り直す。ここを素材の mtime だけで見ていると、著者が
      # typography.*.font を変えても古い書体を抱えた派生が残る（notes §5.1 の取りこぼし）。
      def test_should_rebuild_the_derivative_when_the_font_setting_changes
        skip '同梱書体が無い環境では検証できない' unless File.file?(REAL_FONT)

        with_project(real_font: true) do
          source = write_svg('coords.svg', %(<svg xmlns="http://www.w3.org/2000/svg"><text font-family="sans-serif">座標</text></svg>))
          first = File.read(DerivedSvg.prepare(source))

          install_config(heading: 'Zen Old Mincho')
          second = File.read(DerivedSvg.prepare(source))

          assert_includes first, 'Zen Kaku Gothic New, sans-serif'
          assert_includes second, 'Zen Old Mincho, sans-serif'
        end
      end

      private

      # 書体の実体を置いた一時プロジェクトでブロックを実行する。
      # real_font: true のときだけ同梱の実フォントを持ち込む（サブセットまで通す 1 本用）。
      def with_project(real_font: false)
        original = Common::CONFIG
        Dir.mktmpdir('vs-derived-svg') do |dir|
          Dir.chdir(dir) do
            place_fonts(real_font)
            install_config
            yield
          end
        end
      ensure
        Common.install_configuration!(original)
      end

      # 同梱書体の置き場を再現する。HackGen35 だけディレクトリ名が slug と一致しない
      # （page-settings.css が実ファイルを直に指しているため）ので、実物どおりに置く。
      def place_fonts(real_font)
        {
          'Zen_Kaku_Gothic_New' => %w[ZenKakuGothicNew-Regular.ttf ZenKakuGothicNew-Bold.ttf],
          'Zen_Old_Mincho' => %w[ZenOldMincho-Regular.ttf ZenOldMincho-Bold.ttf],
          'hackgen35' => %w[HackGen35ConsoleNF-Regular.ttf HackGen35ConsoleNF-Bold.ttf]
        }.each do |slug, files|
          FileUtils.mkdir_p(File.join('stylesheets', 'fonts', slug))
          files.each do |name|
            dest = File.join('stylesheets', 'fonts', slug, name)
            real_font ? FileUtils.cp(REAL_FONT, dest) : FileUtils.touch(dest)
          end
        end
      end

      def install_config(heading: 'Zen Kaku Gothic New')
        Common.install_configuration!(
          Common.build_direct_configuration(
            typography: { heading: { font: heading }, body: { font: 'Zen Old Mincho' },
                          code: { font: 'HackGen35 Console NF' } }
          )
        )
      end

      def write_svg(name, content)
        path = File.join('images', name)
        FileUtils.mkdir_p('images')
        File.write(path, content)
        path
      end
    end
  end
end
