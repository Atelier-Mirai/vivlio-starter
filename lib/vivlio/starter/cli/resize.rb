# frozen_string_literal: true

require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: 画像リサイズ/変換ロジック
      # ================================================================
      # 提供機能:
      #   - 画像を WebP に変換（高精細/標準/軽量のプリセット）
      #   - SVG を rsvg-convert → lossless WebP に変換（Techbook モード用）
      # ================================================================
      module ResizeCommands
        module_function

        RESIZE_DESC = {
          high: {
            short: '画像を高品質WebPに変換します',
            long: <<~DESC
              画像を高品質WebPに変換します（quality=90, max_px=2000）。

              対象: .png, .jpg, .jpeg
              出力: 同ディレクトリに .webp

              引数:
                DIR    対象ディレクトリ（省略時は images/）

              使用例:
                vs resize:high
                vs resize:high assets/images
            DESC
          },
          medium: {
            short: '画像を標準品質WebPに変換します',
            long: <<~DESC
              画像を標準品質WebPに変換します（quality=85, max_px=1600）。

              対象: .png, .jpg, .jpeg
              出力: 同ディレクトリに .webp

              引数:
                DIR    対象ディレクトリ（省略時は images/）

              使用例:
                vs resize:medium
                vs resize:medium assets/images
            DESC
          },
          low: {
            short: '画像を軽量品質WebPに変換します',
            long: <<~DESC
              画像を軽量品質WebPに変換します（quality=75, max_px=1200）。

              対象: .png, .jpg, .jpeg
              出力: 同ディレクトリに .webp

              引数:
                DIR    対象ディレクトリ（省略時は images/）

              使用例:
                vs resize:low
                vs resize:low assets/images
            DESC
          },
          default: {
            short: '画像をWebPに変換します（標準品質）',
            long: <<~DESC
              画像をWebPに変換します（標準品質が既定）。

              対象: .png, .jpg, .jpeg
              出力: 同ディレクトリに .webp

              引数:
                DIR    対象ディレクトリ（省略時は images/）

              オプション:
                --force   既存ファイルも強制再生成
                --high    高品質プリセットを使用
                --low     軽量品質プリセットを使用

              使用例:
                vs resize
                vs resize assets/images
                vs resize --high
                vs resize --force
            DESC
          }
        }.freeze

        def included(base); end

        # Samovar/直接呼び出し用: 高品質プリセット
        def execute_resize_high(dir = 'images', options = {})
          execute_resize_with_preset('高精細', dir, options)
        end
        module_function :execute_resize_high

        # Samovar/直接呼び出し用: 標準品質プリセット
        def execute_resize_medium(dir = 'images', options = {})
          execute_resize_with_preset('標準', dir, options)
        end
        module_function :execute_resize_medium

        # Samovar/直接呼び出し用: 軽量品質プリセット
        def execute_resize_low(dir = 'images', options = {})
          execute_resize_with_preset('軽量', dir, options)
        end
        module_function :execute_resize_low

        # Samovar/直接呼び出し用: プリセット指定でリサイズ
        def execute_resize_with_preset(preset_name, dir, options = {})
          ENV['VERBOSE'] = '1' if options[:verbose]
          ENV['FORCE'] = '1' if options[:force]

          presets = {
            '高精細' => { quality: 90, method: 6, max_px: 2000 },
            '標準' => { quality: 85, method: 6, max_px: 1600 },
            '軽量' => { quality: 75, method: 6, max_px: 1200 }
          }

          preset = presets[preset_name]
          unless preset
            Common.log_error("未知のプリセットです: #{preset_name}")
            return
          end

          unless Dir.exist?(dir)
            Common.log_error("ディレクトリが存在しません: #{dir}")
            return
          end

          unless system('which magick >/dev/null 2>&1')
            Common.log_error('Error: ImageMagick (magick) が見つかりません。brew install imagemagick 等で導入してください。')
            return
          end

          patterns = %w[png jpg jpeg JPG JPEG PNG]
          files = patterns.flat_map { |ext| Dir.glob(File.join(dir, "**/*.#{ext}")) }.uniq.sort

          if files.empty?
            Common.log_info("対象画像が見つかりませんでした: #{dir}")
            return
          end

          Common.log_action("画像変換を開始: Preset=#{preset_name}, Dir=#{dir}, Files=#{files.size}")

          files.each do |src|
            dst = src.sub(/\.[^.]+\z/, '.webp')

            if ENV['FORCE'].nil? && File.exist?(dst) && File.mtime(dst) >= File.mtime(src)
              Common.log_info("skip: up-to-date #{dst}")
              next
            end

            FileUtils.mkdir_p(File.dirname(dst))

            cmd = [
              'magick', src,
              '-resize', "#{preset[:max_px]}x#{preset[:max_px]}>",
              '-strip',
              '-quality', preset[:quality].to_s,
              '-define', "webp:method=#{preset[:method]}",
              dst
            ]

            Common.log_info(cmd.join(' '))
            unless system(*cmd)
              Common.log_error("変換に失敗しました: #{src}")
              return
            end
          end

          Common.log_success('画像変換が完了しました')

          # --delete-originals: 変換成功した元ファイルを確認後に削除
          return unless options[:delete_originals]

          converted_originals = files.select { |src| File.exist?(src.sub(/\.[^.]+\z/, '.webp')) }
          if converted_originals.empty?
            Common.log_info('削除対象の元ファイルはありませんでした')
          else
            Common.log_always('⚠️  以下の元画像ファイルを削除しようとしています:')
            converted_originals.each { |f| Common.log_always("  - #{f}") }
            $stdout.print('本当に削除しますか？ [y/N]: ')
            ans = $stdin.gets
            if ans && ans.strip.downcase == 'y'
              converted_originals.each do |f|
                FileUtils.rm_f(f)
                Common.log_info("削除しました: #{f}")
              end
              Common.log_success("元ファイルを削除しました（#{converted_originals.size}件）")
            else
              Common.log_info('元ファイルの削除をキャンセルしました')
            end
          end
        end
        module_function :execute_resize_with_preset

        # SVG → PNG（rsvg-convert）→ lossless WebP（magick）変換
        # Chromium PDF エンジンが SVG 内の <path>/<text> を Type 3 フォントとして
        # 埋め込む問題を回避するため、ビルド前に全 SVG をラスタライズする。
        # @param dirs [Array<String>] 対象ディレクトリの配列
        # @param dpi [Integer] rsvg-convert の DPI（既定: 350）
        def convert_svg_to_webp(dirs, dpi: 350)
          # --- Phase: ツール存在チェック ---
          unless system('which rsvg-convert >/dev/null 2>&1')
            Common.log_error('Error: rsvg-convert が見つかりません。brew install librsvg 等で導入してください。')
            return
          end

          unless system('which magick >/dev/null 2>&1')
            Common.log_error('Error: ImageMagick (magick) が見つかりません。brew install imagemagick 等で導入してください。')
            return
          end

          # --- Phase: SVG ファイル収集 ---
          svg_files = dirs
            .select { Dir.exist?(it) }
            .flat_map { Dir.glob(File.join(it, '**/*.svg')) }
            .uniq.sort

          if svg_files.empty?
            Common.log_info('[SVG→WebP] 対象 SVG ファイルが見つかりませんでした')
            return
          end

          Common.log_action("[SVG→WebP] #{svg_files.size} 件の SVG を変換します（DPI=#{dpi}）")

          # --- Phase: 変換実行 ---
          converted = 0
          svg_files.each do |svg_path|
            webp_path = svg_path.sub(/\.svg\z/i, '.webp')

            # mtime 比較でスキップ（--force 時は強制再生成）
            if ENV['FORCE'].nil? && File.exist?(webp_path) && File.mtime(webp_path) >= File.mtime(svg_path)
              Common.log_info("[SVG→WebP] skip: up-to-date #{webp_path}")
              next
            end

            # Step 1: SVG → PNG（rsvg-convert で高品質ラスタライズ）
            png_tmp = svg_path.sub(/\.svg\z/i, '.svg.tmp.png')
            rsvg_cmd = ['rsvg-convert', '--dpi-x', dpi.to_s, '--dpi-y', dpi.to_s, '-f', 'png', svg_path, '-o', png_tmp]
            Common.log_info("[SVG→WebP] rsvg-convert: #{svg_path}")
            unless system(*rsvg_cmd)
              Common.log_warn("[SVG→WebP] rsvg-convert に失敗しました: #{svg_path}")
              FileUtils.rm_f(png_tmp)
              next
            end

            # Step 2: PNG → lossless WebP（magick で可逆圧縮）
            magick_cmd = ['magick', png_tmp, '-define', 'webp:lossless=true', '-define', 'webp:method=6', '-strip', webp_path]
            Common.log_info("[SVG→WebP] magick lossless: #{webp_path}")
            unless system(*magick_cmd)
              Common.log_warn("[SVG→WebP] magick 変換に失敗しました: #{png_tmp}")
              FileUtils.rm_f(png_tmp)
              next
            end

            # 中間 PNG を削除
            FileUtils.rm_f(png_tmp)
            converted += 1
          end

          Common.log_success("[SVG→WebP] #{converted} 件の SVG を lossless WebP に変換しました")
        end
        module_function :convert_svg_to_webp
      end
    end
  end
end
