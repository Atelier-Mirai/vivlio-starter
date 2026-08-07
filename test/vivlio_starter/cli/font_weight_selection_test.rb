# frozen_string_literal: true

# ================================================================
# Test: font_weight_selection_test.rb
# ================================================================
# テスト対象:
#   FontManager のウェイト選定（Type 3 フォント対策）
#
# 背景:
#   Google Fonts を `family=<名前>` だけで要求していたため既定の 400 が 1 面
#   返るだけで、Bold 字面の無い書体に太字を要求した Chromium が faux-bold を
#   合成し、それを **Type 3 フォント**として PDF へ埋め込んでいた。
#   実測（2026-08-07）: Noto Sans JP 指定の 1 章ビルドで Type 3 が 195 件。
#
#   日本語 Google Fonts 55 書体の調査では**太字を持つのは 24 書体だけ**で、
#   しかも太字のウェイトは書体ごとに違う（Klee One は 600・M PLUS 1p は 600 が無い）。
#   700 決め打ちでは取り逃すため「600 以上で 700 に最も近いもの」を採る。
#   経緯と実測は `type3-font-embedding-notes.md` §6。
#
# 検証方法:
#   実際の HTTP は伴わない。Google Fonts が返す形の CSS 文字列を与えて、
#   どの @font-face が残るかを見る。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/font_manager'

module VivlioStarter
  module CLI
    class FontWeightSelectionTest < Minitest::Test
      # Google Fonts の css2 が返す形（必要な属性だけ）
      def face(weight)
        <<~CSS
          @font-face {
            font-family: 'Test Font';
            font-style: normal;
            font-weight: #{weight};
            src: url(https://fonts.gstatic.com/s/test/#{weight}.ttf) format('truetype');
          }
        CSS
      end

      def css_for(*weights) = weights.map { face(it) }.join("\n")

      def weights_in(css) = css.scan(/font-weight:\s*(\d+)/).flatten.map(&:to_i).sort

      # 400 と 700 だけを残す（全ウェイトを落とすと和文 1 書体で数十 MB になる）
      def test_should_keep_only_regular_and_bold_faces
        css = css_for(100, 200, 300, 400, 500, 600, 700, 800, 900)

        selected = FontManager.select_weight_faces(css, 'Test Font')

        assert_equal [400, 700], weights_in(selected)
      end

      # 700 が無い書体は 600 を太字に採る（Klee One の実例）
      def test_should_pick_nearest_bold_weight_when_700_is_absent
        css = css_for(400, 600)

        selected = FontManager.select_weight_faces(css, 'Klee One')

        assert_equal [400, 600], weights_in(selected)
      end

      # 600 が無い書体は 700 を採る（M PLUS 1p の実例）
      def test_should_pick_700_when_600_is_absent
        css = css_for(100, 300, 400, 500, 700, 800, 900)

        selected = FontManager.select_weight_faces(css, 'M PLUS 1p')

        assert_equal [400, 700], weights_in(selected)
      end

      # 900 しか無ければそれを太字に採る（600 以上なら太字とみなす）
      def test_should_treat_any_weight_at_or_above_600_as_bold
        css = css_for(400, 900)

        selected = FontManager.select_weight_faces(css, 'Test Font')

        assert_equal [400, 900], weights_in(selected)
      end

      # 500 は太字とみなさない——中太を太字に流用すると強調が弱くなる
      def test_should_not_treat_medium_weight_as_bold
        css = css_for(300, 400, 500)

        selected = FontManager.select_weight_faces(css, 'Test Font')

        assert_equal [400], weights_in(selected)
      end

      # 太字が無い書体は著者に伝える（黙って代用すると「指定と違う字が出た」に見える）
      def test_should_warn_when_no_bold_face_is_available
        warned = []
        Common.stub(:log_warn, ->(msg, **) { warned << msg }) do
          FontManager.select_weight_faces(css_for(400), 'Dela Gothic One')
        end

        assert_includes warned.join, 'Dela Gothic One'
        assert_includes warned.join, '太字'
      end

      # 1 面しか返らない CSS はそのまま通す（旧来の要求へフォールバックした場合）
      def test_should_pass_through_single_face_css
        css = css_for(400)

        assert_equal [400], weights_in(FontManager.select_weight_faces(css, 'Test Font'))
      end

      # 同梱書体は Regular/Bold 両字面を持つので常に太字あつかい
      def test_should_report_bundled_fonts_as_having_bold
        FontManager::STANDARD_FONT_FAMILIES.each do |family|
          assert FontManager.bold_available?(family), "#{family} は同梱書体なので太字ありのはずです"
        end
      end

      def test_should_report_blank_font_name_as_having_no_bold
        refute FontManager.bold_available?(nil)
        refute FontManager.bold_available?('   ')
      end
    end
  end
end
