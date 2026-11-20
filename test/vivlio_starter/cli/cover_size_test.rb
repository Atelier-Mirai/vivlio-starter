# frozen_string_literal: true

require_relative '../../test_helper'
require 'tmpdir'
require 'yaml'
require 'vivlio_starter/cli/cover'

module VivlioStarter
  module CLI
    # 判型のプリセットを全部回し、どの判型でも表紙の寸法が決まることを確かめる
    # （cover-size-independence-spec.md §6）。判型を足した人が表紙のことを忘れても、ここが落ちる。
    class CoverSizeTest < Minitest::Test
      PRESETS_FILE = File.expand_path('../../../config/page_presets.yml', __dir__)

      def presets = YAML.safe_load_file(PRESETS_FILE, aliases: true, symbolize_names: true)

      def refute_template_used(name, trim)
        capture_io { assert_equal({ type: :missing }, CoverCommands.resolve_source('front', 'light', trim), name.to_s) }
      end

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

      # 3. 同梱のひな形が使える判型（縦長）では、表と裏とも組み立てられ、viewBox の比が判型と 1% 以内で合う。
      #    使えない判型（横長・正方形）は、ひな形を使わずに 🔴 で著者の画像へ案内する（§4.4）
      def test_should_fit_the_bundled_templates_to_every_portrait_preset
        Dir.mktmpdir('vs-cover-size') do |dir|
          Common.stub(:cover_cache_dir, dir) do
            presets.each do |name, preset|
              trim = CoverCommands.trim_size(preset)
              next refute_template_used(name, trim) unless CoverCommands.bundled_template_fits?(trim)

              %w[front back].each do |side|
                source = File.expand_path("../../../covers/bundled/#{side}cover.svg", __dir__)
                svg = File.read(CoverCommands::SvgCover.render_svg(source, side, 'light', bundled: true, trim:))
                vb_w, vb_h = svg[/viewBox="0 0 ([\d.]+ [\d.]+)"/, 1].split.map(&:to_f)

                assert_in_delta trim.height_mm.to_f / trim.width_mm, vb_h / vb_w, 0.01 * vb_h / vb_w, "#{name} の#{side}cover"
              end
            end
          end
        end
      end

      # 横長の判型（S9-1 で足す B5 の横の寸法を直接書いた本）では、同梱のひな形を使わない
      def test_should_refuse_the_bundled_template_for_a_landscape_size
        trim = CoverCommands.trim_size(width: '257mm', height: '182mm')

        refute CoverCommands.bundled_template_fits?(trim)
        out, err = capture_io { assert_equal({ type: :missing }, CoverCommands.resolve_source('front', 'light', trim)) }
        assert_match(/同梱の表紙（light）は、横長・正方形の判型（257 × 182 mm）では作れません/, out + err)
        assert_match(%r{covers/frontcover_master.png（3541 × 2508 px）}, out + err)
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
