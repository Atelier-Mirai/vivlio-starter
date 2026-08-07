# frozen_string_literal: true

# ================================================================
# Test: pre_process/svg_font_embedder_test.rb
# ================================================================
# テスト対象:
#   SvgFontEmbedder#heading_font_path（見出し書体の実体を探す）
#
# 背景:
#   生成 SVG（showcase / mermaid）は `<img>` 参照の独立文書なので、本文の
#   @font-face が届かない。ラベルの字だけをサブセットにして SVG 自身へ
#   埋め込むことで Type 3 を防いでいる（`type3-font-embedding-notes.md` §5）。
#   その入口がこのメソッドで、書体の実体を見つけられないと埋め込みが黙って
#   行なわれず、SVG が OS の和文フォントへ落ちて Type 3 が戻る。
#
#   置き場もファイル名も 2 通りある。同梱書体は `fonts/<slug>/` に
#   `*-Bold.ttf`、Google Fonts は `fonts/google/<slug>/` に `<Slug>-700.ttf`
#   （400 はウェイト数値なし）。**2026-08-08 まで前者しか見ておらず**、
#   Google Fonts を指定すると Type 3 が再発していた（1 章ビルドで 5 件を再現）。
#
# 検証方法:
#   実フォントは要らない。tmpdir に空の .ttf を規則どおりの名前で置き、
#   どれが選ばれるかだけを見る。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'

module VivlioStarter
  module CLI
    class SvgFontEmbedderTest < Minitest::Test
      Embedder = PreProcessCommands::SvgFontEmbedder

      # 同梱書体は Bold 字面があればそれを選ぶ
      def test_should_prefer_bold_face_of_bundled_font
        with_fonts('Zen Kaku Gothic New',
                   'fonts/Zen_Kaku_Gothic_New' => %w[ZenKakuGothicNew-Regular.ttf ZenKakuGothicNew-Bold.ttf]) do
          assert_equal 'ZenKakuGothicNew-Bold.ttf', File.basename(Embedder.heading_font_path)
        end
      end

      # 同梱書体に Bold が無ければ手持ちの 1 本で代替する
      def test_should_fall_back_to_regular_face_of_bundled_font
        with_fonts('Zen Kaku Gothic New',
                   'fonts/Zen_Kaku_Gothic_New' => %w[ZenKakuGothicNew-Regular.ttf]) do
          assert_equal 'ZenKakuGothicNew-Regular.ttf', File.basename(Embedder.heading_font_path)
        end
      end

      # 回帰: Google Fonts の置き場（fonts/google/<slug>/）も探すこと。
      # ここを見落とすと Google Fonts 指定時だけ Type 3 が再発する。
      def test_should_find_google_font_outside_bundled_dir
        with_fonts('Klee One', 'fonts/google/Klee_One' => %w[Klee-One.ttf Klee-One-600.ttf]) do
          refute_nil Embedder.heading_font_path, 'fonts/google/ を探していません'
        end
      end

      # Google Fonts の太さはファイル名末尾のウェイト数値。最も太い面を選ぶ
      # （400 は数値が付かないので 0 として扱われ、必ず負ける）。
      def test_should_prefer_heaviest_weight_of_google_font
        with_fonts('Klee One', 'fonts/google/Klee_One' => %w[Klee-One.ttf Klee-One-600.ttf]) do
          assert_equal 'Klee-One-600.ttf', File.basename(Embedder.heading_font_path)
        end
      end

      # 同梱と Google に同名の書体があれば同梱を優先する（取得物より手元の実体）
      def test_should_prefer_bundled_over_google_for_same_family
        with_fonts('Zen Kaku Gothic New',
                   'fonts/Zen_Kaku_Gothic_New' => %w[ZenKakuGothicNew-Bold.ttf],
                   'fonts/google/Zen_Kaku_Gothic_New' => %w[Zen-Kaku-Gothic-New.ttf]) do
          assert_equal 'ZenKakuGothicNew-Bold.ttf', File.basename(Embedder.heading_font_path)
        end
      end

      # 実体がどこにも無ければ nil（呼び出し側は埋め込みを諦める）
      def test_should_return_nil_when_font_is_missing
        with_fonts('Nonexistent Font') do
          assert_nil Embedder.heading_font_path
        end
      end

      private

      # 見出し書体を name に設定し、layout の { 相対ディレクトリ => ファイル名の配列 } を
      # tmpdir へ空ファイルとして置いた状態でブロックを実行する。
      def with_fonts(name, layout = {})
        original = Common::CONFIG
        Dir.mktmpdir('vs-svg-font') do |dir|
          Dir.chdir(dir) do
            layout.each do |rel, files|
              FileUtils.mkdir_p(File.join('stylesheets', rel))
              files.each { FileUtils.touch(File.join('stylesheets', rel, it)) }
            end
            Common.install_configuration!(Common.build_direct_configuration(typography: { heading: { font: name } }))
            yield
          end
        end
      ensure
        Common.install_configuration!(original)
      end
    end
  end
end
