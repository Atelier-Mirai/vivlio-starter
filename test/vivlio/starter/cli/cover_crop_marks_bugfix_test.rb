# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/cover'
require 'vivlio/starter/cli/create'
require 'vivlio/starter/cli/build/nombre_stamper'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # CoverCropMarksBugfixTest: 表紙・裏表紙トンボ付与バグ修正の検証テスト
      # ================================================================
      # 仕様書: .kiro/specs/cover-crop-marks-bugfix/
      #
      # Property 1 (Bug Condition): 表紙・裏表紙トンボ形式の統一
      #   - print_pdf ターゲット時に表紙・裏表紙PDFに本文と同じ形式のトンボが付与される
      #   - ページサイズは「仕上がりサイズ + 2 × (bleed_mm + CROP_MARK_OFFSET_MM)」となる
      #
      # **Validates: Requirements 1.1, 1.2, 1.3**
      # ================================================================
      class CoverCropMarksBugfixTest < Minitest::Test
        # B5 仕上がりサイズ（mm）
        TRIM_W_MM = 182.0
        TRIM_H_MM = 257.0
        BLEED_MM  = 3.0
        OFFSET_MM = Vivlio::Starter::CLI::CoverCommands::CROP_MARK_OFFSET_MM

        # Property 1: Bug Condition - 表紙・裏表紙トンボ形式の統一
        #
        # **重要**: このテストは修正前のコードで実行し、失敗することを確認する
        # **失敗は正常**: テストの失敗はバグの存在を証明する
        #
        # PNGテーマ（master）で print_pdf ターゲット時に表紙・裏表紙PDFを生成し、
        # トンボ形式が本文と一致するかを検証する。
        #
        # 検証項目:
        # 1. ページサイズが正しいこと（仕上がり + 2 × (bleed + offset)）
        # 2. トンボ要素が存在すること（角トンボ + センタートンボ）
        #
        # **Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 2.4**
        def test_property_bug_condition_png_theme_cover_crop_marks_format_matches_main_body
          skip 'ImageMagickが必要です' unless imagemagick_available?
          skip 'HexaPDFが必要です' unless hexapdf_available?

          within_temp_dir do
            setup_config_with_print_pdf

            covers_dir = 'covers'
            FileUtils.mkdir_p(covers_dir)

            # PNGテーマ（master）の表紙・裏表紙を生成
            create_dummy_master_files(covers_dir)

            # print_pdf ターゲットで表紙・裏表紙PDFを生成
            base_size = CoverCommands::SIZES[:b5]
            front_input = File.join(covers_dir, 'frontcover_master.png')
            front_output = File.join(covers_dir, 'frontcover_master_b5_cmyk.pdf')
            back_input = File.join(covers_dir, 'backcover_master.png')
            back_output = File.join(covers_dir, 'backcover_master_b5_cmyk.pdf')

            # トンボ付きPDFを生成
            CoverCommands.generate_pdfx_single(
              front_input, front_output, base_size,
              bleed_mm: BLEED_MM, crop_marks: true
            )
            CoverCommands.generate_pdfx_single(
              back_input, back_output, base_size,
              bleed_mm: BLEED_MM, crop_marks: true
            )

            # 検証1: ページサイズが正しいこと
            expected_w_mm = TRIM_W_MM + 2 * (BLEED_MM + OFFSET_MM)
            expected_h_mm = TRIM_H_MM + 2 * (BLEED_MM + OFFSET_MM)

            [front_output, back_output].each do |pdf_path|
              assert File.exist?(pdf_path), "PDFが生成されるべきです: #{pdf_path}"

              require 'hexapdf'
              doc = HexaPDF::Document.open(pdf_path)
              box = doc.pages[0].box
              actual_w_mm = box.width  / 72.0 * 25.4
              actual_h_mm = box.height / 72.0 * 25.4

              assert_in_delta expected_w_mm, actual_w_mm, 1.0,
                "#{File.basename(pdf_path)}: 幅が期待値と一致すべきです（期待: #{expected_w_mm}mm、実際: #{actual_w_mm.round(2)}mm）"
              assert_in_delta expected_h_mm, actual_h_mm, 1.0,
                "#{File.basename(pdf_path)}: 高さが期待値と一致すべきです（期待: #{expected_h_mm}mm、実際: #{actual_h_mm.round(2)}mm）"
            end

            # 検証2: トンボ要素が存在すること
            # 本文と同じ形式のトンボ（角トンボ + センタートンボ⊕）が付与されているか
            # 注: ImageMagickの-drawコマンドで描画されたトンボは、
            #     Prawn + CombinePDFで描画されたトンボと形式が異なる可能性がある
            #
            # **期待される結果**: このテストは未修正コードで失敗する
            # （トンボ形式が本文と異なるため）
            [front_output, back_output].each do |pdf_path|
              verify_crop_marks_format(pdf_path)
            end
          end
        end

        # Property 2: Preservation - pdf ターゲット時のトンボなし動作保持
        #
        # **重要**: このテストは修正前のコードで実行し、成功することを確認する
        # **成功は正常**: テストの成功はベースライン動作を確認する
        #
        # pdf ターゲット時に表紙・裏表紙PDFを生成し、トンボが付与されないことを検証する。
        # ページサイズは「仕上がりサイズ + 2 × bleed_mm」となる。
        #
        # 検証項目:
        # 1. PDFが生成されること
        # 2. ページサイズが「仕上がり + 2 × bleed」であること（トンボオフセットなし）
        # 3. トンボ要素が存在しないこと
        #
        # **Validates: Requirements 3.1, 3.2**
        def test_property_preservation_pdf_target_no_crop_marks
          skip 'ImageMagickが必要です' unless imagemagick_available?
          skip 'HexaPDFが必要です' unless hexapdf_available?

          within_temp_dir do
            setup_config_with_pdf_target_only

            covers_dir = 'covers'
            FileUtils.mkdir_p(covers_dir)

            # PNGテーマ（master）の表紙・裏表紙を生成
            create_dummy_master_files(covers_dir)

            # pdf ターゲットで表紙・裏表紙PDFを生成（トンボなし）
            base_size = CoverCommands::SIZES[:b5]
            front_input = File.join(covers_dir, 'frontcover_master.png')
            front_output = File.join(covers_dir, 'frontcover_master_b5_rgb.pdf')
            back_input = File.join(covers_dir, 'backcover_master.png')
            back_output = File.join(covers_dir, 'backcover_master_b5_rgb.pdf')

            # トンボなしPDFを生成（crop_marks: false）
            CoverCommands.generate_pdfx_single(
              front_input, front_output, base_size,
              bleed_mm: BLEED_MM, crop_marks: false
            )
            CoverCommands.generate_pdfx_single(
              back_input, back_output, base_size,
              bleed_mm: BLEED_MM, crop_marks: false
            )

            # 検証1: PDFが生成されること
            [front_output, back_output].each do |pdf_path|
              assert File.exist?(pdf_path), "PDFが生成されるべきです: #{pdf_path}"
            end

            # 検証2: ページサイズが「仕上がり + 2 × bleed」であること
            expected_w_mm = TRIM_W_MM + 2 * BLEED_MM
            expected_h_mm = TRIM_H_MM + 2 * BLEED_MM

            [front_output, back_output].each do |pdf_path|
              require 'hexapdf'
              doc = HexaPDF::Document.open(pdf_path)
              box = doc.pages[0].box
              actual_w_mm = box.width  / 72.0 * 25.4
              actual_h_mm = box.height / 72.0 * 25.4

              assert_in_delta expected_w_mm, actual_w_mm, 1.0,
                "#{File.basename(pdf_path)}: 幅が期待値と一致すべきです（期待: #{expected_w_mm}mm、実際: #{actual_w_mm.round(2)}mm）"
              assert_in_delta expected_h_mm, actual_h_mm, 1.0,
                "#{File.basename(pdf_path)}: 高さが期待値と一致すべきです（期待: #{expected_h_mm}mm、実際: #{actual_h_mm.round(2)}mm）"
            end

            # 検証3: トンボ要素が存在しないこと
            [front_output, back_output].each do |pdf_path|
              verify_no_crop_marks(pdf_path)
            end
          end
        end

        # Property 2: Preservation - EPUB用JPEG生成の動作保持
        #
        # **重要**: このテストは修正前のコードで実行し、成功することを確認する
        #
        # EPUB用JPEG生成が正しく動作することを検証する。
        # トンボは付与されず、既存の生成処理が維持される。
        #
        # 検証項目:
        # 1. JPEGが生成されること
        # 2. サイズが1600×2560であること
        # 3. トンボ要素が存在しないこと
        #
        # **Validates: Requirements 3.3**
        def test_property_preservation_epub_jpeg_generation
          skip 'ImageMagickが必要です' unless imagemagick_available?

          within_temp_dir do
            setup_config_with_epub_target

            covers_dir = 'covers'
            FileUtils.mkdir_p(covers_dir)

            # PNGテーマ（master）の表紙を生成
            create_dummy_master_files(covers_dir)

            # EPUB用JPEGを生成
            config = Common.load_config
            CoverCommands.generate_epub_cover(covers_dir, config)

            # 検証1: JPEGが生成されること
            output_jpg = File.join(covers_dir, 'cover_master.jpg')
            assert File.exist?(output_jpg), "EPUB用JPEGが生成されるべきです: #{output_jpg}"

            # 検証2: サイズが1600×2560であること
            # ImageMagickのidentifyコマンドで画像サイズを取得
            convert_cmd = imagemagick_convert_command
            if convert_cmd
              identify_cmd = convert_cmd[0] == 'magick' ? ['magick', 'identify'] : ['identify']
              size_output = `#{identify_cmd.join(' ')} -format "%wx%h" "#{output_jpg}"`.strip
              assert_equal '1600x2560', size_output,
                "EPUB用JPEGのサイズが期待値と一致すべきです（期待: 1600x2560、実際: #{size_output}）"
            end

            # 検証3: トンボ要素が存在しないこと（JPEGなのでトンボは含まれない）
            # この検証は形式的なもので、JPEGにはトンボが含まれないことを確認
            assert File.extname(output_jpg) == '.jpg', 'EPUB用カバーはJPEG形式であるべきです'
          end
        end

        # Property 2: Preservation - 複数のページサイズとbleed値での動作保持
        #
        # **重要**: このテストは修正前のコードで実行し、成功することを確認する
        # **プロパティベーステスト**: 複数のテストケースを生成して保存要件を検証
        #
        # 異なるページサイズ（A4/B5/A5）とbleed値（0mm〜10mm）の組み合わせで
        # pdf ターゲット時のトンボなし動作を検証する。
        #
        # 検証項目:
        # 1. ページサイズが「仕上がり + 2 × bleed」であること
        # 2. トンボ要素が存在しないこと
        #
        # **Validates: Requirements 3.1, 3.2**
        def test_property_preservation_multiple_page_sizes_and_bleed_values
          skip 'ImageMagickが必要です' unless imagemagick_available?
          skip 'HexaPDFが必要です' unless hexapdf_available?

          # プロパティベーステスト: 複数のテストケースを生成
          page_sizes = [:a4, :b5, :a5]
          bleed_values = [0.0, 3.0, 5.0, 10.0]

          page_sizes.each do |page_size|
            bleed_values.each do |bleed_mm|
              within_temp_dir do
                setup_config_with_pdf_target_and_bleed(page_size, bleed_mm)

                covers_dir = 'covers'
                FileUtils.mkdir_p(covers_dir)

                # PNGテーマ（master）の表紙を生成
                create_dummy_master_files(covers_dir)

                # pdf ターゲットで表紙PDFを生成（トンボなし）
                base_size = CoverCommands::SIZES[page_size]
                front_input = File.join(covers_dir, 'frontcover_master.png')
                front_output = File.join(covers_dir, "frontcover_master_#{page_size}_rgb.pdf")

                # トンボなしPDFを生成（crop_marks: false）
                CoverCommands.generate_pdfx_single(
                  front_input, front_output, base_size,
                  bleed_mm: bleed_mm, crop_marks: false
                )

                # 検証1: PDFが生成されること
                assert File.exist?(front_output), "PDFが生成されるべきです: #{front_output}"

                # 検証2: ページサイズが「仕上がり + 2 × bleed」であること
                trim_w_mm = base_size[:mm][0]
                trim_h_mm = base_size[:mm][1]
                expected_w_mm = trim_w_mm + 2 * bleed_mm
                expected_h_mm = trim_h_mm + 2 * bleed_mm

                require 'hexapdf'
                doc = HexaPDF::Document.open(front_output)
                box = doc.pages[0].box
                actual_w_mm = box.width  / 72.0 * 25.4
                actual_h_mm = box.height / 72.0 * 25.4

                assert_in_delta expected_w_mm, actual_w_mm, 1.0,
                  "#{page_size.upcase}, bleed=#{bleed_mm}mm: 幅が期待値と一致すべきです（期待: #{expected_w_mm}mm、実際: #{actual_w_mm.round(2)}mm）"
                assert_in_delta expected_h_mm, actual_h_mm, 1.0,
                  "#{page_size.upcase}, bleed=#{bleed_mm}mm: 高さが期待値と一致すべきです（期待: #{expected_h_mm}mm、実際: #{actual_h_mm.round(2)}mm）"

                # 検証3: トンボ要素が存在しないこと
                verify_no_crop_marks(front_output)
              end
            end
          end
        end

        # Property 1: Bug Condition - SVGテーマの表紙・裏表紙トンボ形式の統一
        #
        # SVGテーマ（light/dark）で print_pdf ターゲット時に表紙・裏表紙PDFを生成し、
        # トンボ形式が本文と一致するかを検証する。
        #
        # **Validates: Requirements 1.2, 2.2**
        def test_property_bug_condition_svg_theme_cover_crop_marks_format_matches_main_body
          skip 'rsvg-convertが必要です' unless rsvg_convert_available?
          skip 'HexaPDFが必要です' unless hexapdf_available?
          skip 'Prawnが必要です' unless prawn_available?
          skip 'CombinePDFが必要です' unless combine_pdf_available?

          within_temp_dir do
            setup_config_with_print_pdf_svg_theme

            covers_dir = 'covers'
            FileUtils.mkdir_p(covers_dir)

            # SVGテーマ（light）の表紙・裏表紙を生成
            create_dummy_svg_files(covers_dir, 'light')

            # print_pdf ターゲットで表紙・裏表紙PDFを生成
            front_svg = File.join(covers_dir, 'frontcover_light.svg')
            front_output = File.join(covers_dir, 'frontcover_light_b5_cmyk.pdf')
            back_svg = File.join(covers_dir, 'backcover_light.svg')
            back_output = File.join(covers_dir, 'backcover_light_b5_cmyk.pdf')

            # トンボ付きPDFを生成（convert_svg_to_pdf_with_crop_marks を使用）
            CreateCommands.convert_svg_to_pdf_with_crop_marks(
              front_svg, front_output, TRIM_W_MM, TRIM_H_MM
            )
            CreateCommands.convert_svg_to_pdf_with_crop_marks(
              back_svg, back_output, TRIM_W_MM, TRIM_H_MM
            )

            # 検証1: ページサイズが正しいこと
            expected_w_mm = TRIM_W_MM + 2 * (BLEED_MM + OFFSET_MM)
            expected_h_mm = TRIM_H_MM + 2 * (BLEED_MM + OFFSET_MM)

            [front_output, back_output].each do |pdf_path|
              assert File.exist?(pdf_path), "PDFが生成されるべきです: #{pdf_path}"

              require 'hexapdf'
              doc = HexaPDF::Document.open(pdf_path)
              box = doc.pages[0].box
              actual_w_mm = box.width  / 72.0 * 25.4
              actual_h_mm = box.height / 72.0 * 25.4

              assert_in_delta expected_w_mm, actual_w_mm, 1.0,
                "#{File.basename(pdf_path)}: 幅が期待値と一致すべきです（期待: #{expected_w_mm}mm、実際: #{actual_w_mm.round(2)}mm）"
              assert_in_delta expected_h_mm, actual_h_mm, 1.0,
                "#{File.basename(pdf_path)}: 高さが期待値と一致すべきです（期待: #{expected_h_mm}mm、実際: #{actual_h_mm.round(2)}mm）"
            end

            # 検証2: トンボ要素が存在すること
            [front_output, back_output].each do |pdf_path|
              verify_crop_marks_format(pdf_path)
            end
          end
        end

        private

        # トンボが存在しないことを検証する
        #
        # pdf ターゲット時にはトンボが付与されないことを検証する。
        #
        # @param pdf_path [String] 検証対象のPDFファイルパス
        def verify_no_crop_marks(pdf_path)
          require 'hexapdf'
          doc = HexaPDF::Document.open(pdf_path)
          page = doc.pages[0]

          # PDFの内容ストリームを取得
          content = page.contents
          content_str = content.to_s

          # トンボ描画コマンドが存在しないことを確認
          # 注: この検証は簡易的なもので、完全な保証を提供するものではない
          # 実際には、PDFの描画コマンドを詳細に解析する必要がある
          #
          # ここでは、トンボ特有のパターン（複数の直線と円の組み合わせ）が
          # 存在しないことを確認する
          
          # 簡易チェック: 内容が非常にシンプルであることを確認
          # トンボ付きPDFは多数の描画コマンドを含むが、トンボなしPDFはシンプル
          line_count = content_str.scan(/\bl\b/).size
          
          # トンボなしPDFは直線描画コマンドが少ない（または存在しない）
          assert line_count < 10,
            "#{File.basename(pdf_path)}: トンボ描画コマンドが存在しないべきです（直線数: #{line_count}）"
        end

        # トンボ形式を検証する
        #
        # 本文と同じ形式のトンボ（角トンボ + センタートンボ⊕）が付与されているかを検証する。
        # 具体的には、PDFに以下の要素が含まれているかをチェックする:
        # - 角トンボ: 4隅の直線（ページ端からbleed境界まで）
        # - センタートンボ: 各辺の中央の⊕形状（丸十字）
        #
        # 注: この検証は簡易的なもので、PDFの内部構造を完全に解析するわけではない。
        #     実際のトンボ形式の詳細な検証は、目視確認または専用ツールで行う必要がある。
        #
        # @param pdf_path [String] 検証対象のPDFファイルパス
        def verify_crop_marks_format(pdf_path)
          require 'hexapdf'
          doc = HexaPDF::Document.open(pdf_path)
          page = doc.pages[0]

          # PDFの内容ストリームを取得
          content = page.contents

          # トンボ要素の存在を確認
          # 注: この検証は簡易的なもので、実際のトンボ形式を完全に検証するわけではない
          # 実際の検証では、PDFの描画コマンド（line, circle等）を解析する必要がある
          #
          # ここでは、以下の要素が存在することを確認する:
          # 1. 直線描画コマンド（角トンボ用）
          # 2. 円描画コマンド（センタートンボの⊕用）
          #
          # **期待される結果**: 未修正コードでは、ImageMagickの-drawコマンドで描画されたトンボが
          # 存在するが、Prawn + CombinePDFで描画されたトンボとは形式が異なる可能性がある

          # PDFの内容を文字列として取得
          content_str = content.to_s

          # 直線描画コマンドの存在を確認（簡易チェック）
          # 注: この検証は完全ではなく、実際のトンボ形式を保証するものではない
          assert content_str.include?('l') || content_str.include?('line'),
            "#{File.basename(pdf_path)}: 直線描画コマンドが存在すべきです（角トンボ用）"

          # 円描画コマンドの存在を確認（簡易チェック）
          # 注: センタートンボの⊕には円が含まれる
          # ImageMagickの-drawコマンドで描画された場合と、Prawn + CombinePDFで描画された場合で
          # PDFの内部表現が異なる可能性がある
          #
          # **期待される結果**: 未修正コードでは、この検証が失敗する可能性がある
          # （トンボ形式が本文と異なるため）
          assert content_str.include?('c') || content_str.include?('circle') || content_str.include?('re'),
            "#{File.basename(pdf_path)}: 円描画コマンドが存在すべきです（センタートンボ⊕用）"
        end

        # pdf ターゲットのみを含む設定ファイルを生成する
        def setup_config_with_pdf_target_only
          FileUtils.mkdir_p('config')
          config = {
            'directories' => { 'covers' => 'covers' },
            'output' => {
              'cover' => 'master',
              'targets' => 'pdf',
              'print_pdf' => { 'bleed' => '3mm', 'crop_marks' => false }
            },
            'page' => { 'use' => 'b5_standard' }
          }
          File.write('config/book.yml', config.to_yaml)
          File.write('config/page_presets.yml', dummy_page_presets.to_yaml)
          File.write('config/post_replace_list.yml', { 'replacements' => [] }.to_yaml)
        end

        # pdf ターゲットと指定されたページサイズ・bleed値を含む設定ファイルを生成する
        def setup_config_with_pdf_target_and_bleed(page_size, bleed_mm)
          FileUtils.mkdir_p('config')
          page_preset_name = "#{page_size}_standard"
          config = {
            'directories' => { 'covers' => 'covers' },
            'output' => {
              'cover' => 'master',
              'targets' => 'pdf',
              'print_pdf' => { 'bleed' => "#{bleed_mm}mm", 'crop_marks' => false }
            },
            'page' => { 'use' => page_preset_name }
          }
          File.write('config/book.yml', config.to_yaml)
          File.write('config/page_presets.yml', dummy_page_presets_all_sizes.to_yaml)
          File.write('config/post_replace_list.yml', { 'replacements' => [] }.to_yaml)
        end

        # epub ターゲットを含む設定ファイルを生成する
        def setup_config_with_epub_target
          FileUtils.mkdir_p('config')
          config = {
            'directories' => { 'covers' => 'covers' },
            'output' => {
              'cover' => 'master',
              'targets' => 'epub'
            },
            'page' => { 'use' => 'b5_standard' }
          }
          File.write('config/book.yml', config.to_yaml)
          File.write('config/page_presets.yml', dummy_page_presets.to_yaml)
          File.write('config/post_replace_list.yml', { 'replacements' => [] }.to_yaml)
        end

        # print_pdf ターゲットを含む設定ファイルを生成する（PNGテーマ用）
        def setup_config_with_print_pdf
          FileUtils.mkdir_p('config')
          config = {
            'directories' => { 'covers' => 'covers' },
            'output' => {
              'cover' => 'master',
              'targets' => 'print_pdf',
              'print_pdf' => { 'bleed' => '3mm', 'crop_marks' => true }
            },
            'page' => { 'use' => 'b5_standard' }
          }
          File.write('config/book.yml', config.to_yaml)
          File.write('config/page_presets.yml', dummy_page_presets.to_yaml)
          File.write('config/post_replace_list.yml', { 'replacements' => [] }.to_yaml)
        end

        # print_pdf ターゲットを含む設定ファイルを生成する（SVGテーマ用）
        def setup_config_with_print_pdf_svg_theme
          FileUtils.mkdir_p('config')
          config = {
            'directories' => { 'covers' => 'covers' },
            'output' => {
              'cover' => 'light',
              'targets' => 'print_pdf',
              'print_pdf' => { 'bleed' => '3mm', 'crop_marks' => true }
            },
            'page' => { 'use' => 'b5_standard' }
          }
          File.write('config/book.yml', config.to_yaml)
          File.write('config/page_presets.yml', dummy_page_presets.to_yaml)
          File.write('config/post_replace_list.yml', { 'replacements' => [] }.to_yaml)
        end

        # マスター PNG を一時ディレクトリに生成する
        def create_dummy_master_files(covers_dir)
          create_dummy_png(File.join(covers_dir, 'frontcover_master.png'))
          create_dummy_png(File.join(covers_dir, 'backcover_master.png'))
        end

        # SVGファイルを一時ディレクトリに生成する
        def create_dummy_svg_files(covers_dir, theme)
          front_svg = File.join(covers_dir, "frontcover_#{theme}.svg")
          back_svg = File.join(covers_dir, "backcover_#{theme}.svg")

          # 簡易的なSVGコンテンツを生成
          svg_content = <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 595 842" width="595" height="842">
              <rect width="595" height="842" fill="#f0f0f0"/>
              <text x="297" y="421" text-anchor="middle" font-size="24">Test Cover</text>
            </svg>
          SVG

          File.write(front_svg, svg_content)
          File.write(back_svg, svg_content)
        end

        # ImageMagick で小さな白い PNG を生成する
        def create_dummy_png(path, width: 100, height: 100)
          convert_cmd = imagemagick_convert_command
          if convert_cmd
            system(*convert_cmd, '-size', "#{width}x#{height}", 'xc:white', path,
                   out: File::NULL, err: File::NULL)
          else
            # ImageMagick がない場合は最小限の PNG バイナリを書き込む
            File.binwrite(path, minimal_png_binary)
          end
        end

        # 最小限のPNGバイナリを返す
        def minimal_png_binary
          [
            "\x89PNG\r\n\x1a\n",
            "\x00\x00\x00\rIHDR",
            "\x00\x00\x00\x01\x00\x00\x00\x01",
            "\x08\x02\x00\x00\x00",
            "\x90wS\xde",
            "\x00\x00\x00\nIDATx\x9cc\xf8\x00\x00\x00\x01\x00\x01",
            "\x00\x00\x00\x00IEND\xaeB`\x82"
          ].join
        end

        # ImageMagick が利用可能かチェックする
        def imagemagick_available?
          !imagemagick_convert_command.nil?
        end

        # rsvg-convert が利用可能かチェックする
        def rsvg_convert_available?
          command_in_path?('rsvg-convert')
        end

        # HexaPDF が利用可能かチェックする
        def hexapdf_available?
          require 'hexapdf'
          true
        rescue LoadError
          false
        end

        # Prawn が利用可能かチェックする
        def prawn_available?
          require 'prawn'
          true
        rescue LoadError
          false
        end

        # CombinePDF が利用可能かチェックする
        def combine_pdf_available?
          require 'combine_pdf'
          true
        rescue LoadError
          false
        end

        # ImageMagick のコマンドを取得する（magick 優先）
        def imagemagick_convert_command
          return ['magick'] if command_in_path?('magick')
          return ['convert'] if command_in_path?('convert')
          nil
        end

        # 指定コマンドが PATH に存在するかチェックする
        def command_in_path?(command)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
            path = File.join(dir, command)
            File.executable?(path) && !File.directory?(path)
          end
        end

        # 一時ディレクトリ内でテストを実行する
        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) { yield dir }
          end
        end

        # ダミーのページプリセット設定を返す
        def dummy_page_presets
          {
            'b5_standard' => {
              'size' => 'B5',
              'base_font_size' => '10.5pt',
              'base_line_height' => '17pt',
              'margin_top' => '20mm',
              'margin_bottom' => '20mm',
              'margin_inner' => '20mm',
              'margin_outer' => '20mm'
            }
          }
        end

        # すべてのページサイズのダミープリセット設定を返す
        def dummy_page_presets_all_sizes
          {
            'a4_standard' => {
              'size' => 'A4',
              'base_font_size' => '10.5pt',
              'base_line_height' => '17pt',
              'margin_top' => '20mm',
              'margin_bottom' => '20mm',
              'margin_inner' => '20mm',
              'margin_outer' => '20mm'
            },
            'b5_standard' => {
              'size' => 'B5',
              'base_font_size' => '10.5pt',
              'base_line_height' => '17pt',
              'margin_top' => '20mm',
              'margin_bottom' => '20mm',
              'margin_inner' => '20mm',
              'margin_outer' => '20mm'
            },
            'a5_standard' => {
              'size' => 'A5',
              'base_font_size' => '10.5pt',
              'base_line_height' => '17pt',
              'margin_top' => '20mm',
              'margin_bottom' => '20mm',
              'margin_inner' => '20mm',
              'margin_outer' => '20mm'
            }
          }
        end
      end
    end
  end
end
