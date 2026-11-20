# frozen_string_literal: true

require_relative '../../test_helper'
require 'yaml'
require 'vivlio_starter/cli/cover'

module VivlioStarter
  module CLI
    # 判型のプリセットを全部回し、どの判型でも表紙の寸法が決まることを確かめる
    # （cover-size-independence-spec.md §6）。判型を足した人が表紙のことを忘れても、ここが落ちる。
    class CoverSizeTest < Minitest::Test
      PRESETS_FILE = File.expand_path('../../../config/page_presets.yml', __dir__)

      def presets = YAML.safe_load_file(PRESETS_FILE, aliases: true, symbolize_names: true)

      # 1. 窓口が幅と高さ（mm）・画素数・名前を返す。画素数は mm を 350dpi にした値
      # 2. 名前がファイル名に使える字（英小文字・数字・x）だけ
      def test_should_resolve_a_trim_size_for_every_preset
        presets.each do |name, preset|
          trim = CoverCommands.trim_size(preset)

          refute_nil trim, "#{name} の表紙の寸法が決まりません（Common::PAGE_SIZES に #{preset[:size]} があるか）"
          assert_equal trim.mm.map { (it / Units::MM_PER_INCH * CoverCommands::DPI).round }, [trim.width, trim.height], name.to_s
          assert_match(/\A[a-z0-9x]+\z/, trim.name, "#{name} の判型の名前はファイル名に使える字だけにする")
        end
      end

      # 本文の @page と表紙が同じ寸法になる（本文と表紙が別の表を持たない。§2.1）
      def test_should_give_the_cover_and_the_body_the_same_size
        presets.each do |name, preset|
          body = Common.resolve_page_size(preset).map { Units.length_to_mm(it) }

          assert_equal body, CoverCommands.trim_size(preset).mm, name.to_s
        end
      end

      # 小説の判型（novel-vertical-spec.md §4.1）の寸法と、生成物のファイル名に出る名前
      def test_should_size_the_novel_presets
        expected = {
          a6_standard: [[105, 148], 'a6'], b6_standard: [[128, 182], 'b6'],
          shinsho_standard: [[103, 182], 'shinsho'], shiroku_standard: [[127, 188], 'shiroku']
        }
        expected.each do |name, (mm, file_name)|
          trim = CoverCommands.trim_size(presets.fetch(name))

          assert_equal [mm, file_name], [trim.mm, trim.name], name.to_s
        end
      end

      # 版面の字数と行数が §4.1 の目安になるよう、余白を字の大きさの整数倍で決めてある。
      # 縦書きでは字数が天地、行数がノドと小口の間に入る
      def test_should_fit_the_target_characters_and_lines_in_the_novel_presets
        { a6_standard: [38, 16], b6_standard: [42, 17], shinsho_standard: [44, 15], shiroku_standard: [43, 17] }
          .each do |name, (chars, lines)|
            preset = presets.fetch(name)
            width, height = Common.resolve_page_size(preset).map { Units.length_to_mm(it) }
            font = Units.length_to_mm(preset[:base_font_size])
            advance = font * preset[:base_line_height]
            area_h = height - Units.length_to_mm(preset[:margin_top]) - Units.length_to_mm(preset[:margin_bottom])
            area_w = width - Units.length_to_mm(preset[:margin_inner]) - Units.length_to_mm(preset[:margin_outer])

            assert_in_delta chars, area_h / font, 0.01, "#{name} の字数"
            assert_equal lines, ((area_w - font) / advance).floor + 1, "#{name} の行数"
            assert_operator Units.length_to_mm(preset[:margin_inner]), :>=, 13, "#{name} のノドは 13mm 以上"
          end
      end
    end
  end
end
