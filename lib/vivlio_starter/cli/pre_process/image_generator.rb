# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/image_generator.rb
# ================================================================
# 責務:
#   テーマ画像のバリアント（portrait/landscape）を生成する。
#   左上と右下に飾りを置いた元画像を対角線で 2 つに分け、飾りの間を広げて置き直す。
#
# 生成処理:
#   1. ImageMagick で透明な余白を除き、対角線で分けて指定の縦横比の画布へ置き直す
#   2. 仕上がりの幅の 2/3 に満たない小さい絵だけ、waifu2x-ncnn-vulkan で 2x アップスケール
#      + ノイズ除去（あれば）。大きい絵は ImageMagick で拡大・縮小する（改善案 #143）
#   3. WebP 形式で出力（quality=90）
#
# バリアント:
#   - portrait: 扉絵用（ページ比率に合わせた縦長）
#   - landscape: 飾り画像用（2.39:1 シネマスコープ横長）
#
# 依存:
#   - waifu2x-ncnn-vulkan: GPU 高速化画像拡大
#   - ImageMagick: クロップ・変換
# ================================================================

require 'open3'
require 'fileutils'
require 'tmpdir'
require 'shellwords'
require_relative '../common'
require_relative 'theme_image_resolver'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # テーマ画像バリアント生成モジュール
      module ImageGenerator
        DEFAULT_WAIFU2X_BIN = File.expand_path('~/.local/bin/waifu2x/waifu2x-ncnn-vulkan')
        FRONTISPIECE_WAIFU2X_NOISE = 1
        FRONTISPIECE_SCALE = 2
        FRONTISPIECE_TARGET_WIDTH = 2880 # frontispiece推奨横幅
        FRONTISPIECE_WEBP_QUALITY = 90
        # 並べ直した絵の幅が仕上がりの幅のこの割合以上なら、waifu2x を通さず ImageMagick で
        # 拡大・縮小する（改善案 #143）。2/3 の絵では waifu2x あり・なしの差が PSNR で 0.5 dB と
        # 見分けられず、1/2 以下では waifu2x のほうが細部が残った。waifu2x は 1 枚の絵に
        # 約 36 秒かかる（ImageMagick だけなら約 9 秒）。仕上がりより広い節絵は縮めるだけで済む
        WAIFU2X_SKIP_WIDTH_RATIO = 2.0 / 3

        # 扉絵・節絵の作り方の版。作り方を変えて、作った絵が変わるときに上げる。
        # 2: 透過を透過のまま運ぶ（改善案 #140）
        VARIANT_REVISION = 2
        VARIANT_REVISION_STAMP = '.variant-revision'

        module_function

        # 作り方の版が生成キャッシュの版と違えば、生成キャッシュの扉絵・節絵を捨てる。
        # 作り直すかは元の絵の更新日時でも決めるが、作り方を変えても元の絵の日時は
        # 変わらない。版を見ないと、利用者の絵から作った古い扉絵が使われ続ける。
        # 確かめるのはキャッシュの置き場ごとに 1 プロセス 1 回（テストは置き場を差し替える）。
        def discard_outdated_variants!
          root = ThemeImageResolver.theme_images_cache_root
          return if @revision_checked_root == root

          @revision_checked_root = root
          stamp = File.join(root, VARIANT_REVISION_STAMP)
          return if File.exist?(stamp) && File.read(stamp).strip == VARIANT_REVISION.to_s

          FileUtils.rm_f(Dir.glob(File.join(root, '**', '*_{portrait,landscape}.webp')))
          FileUtils.mkdir_p(root)
          File.write(stamp, "#{VARIANT_REVISION}\n")
        end

        def frontispiece_variants
          portrait_ratio = ThemeImageResolver.binding_safe_portrait_ratio
          {
            portrait: portrait_ratio,
            landscape: (1.0 / 2.39) # ornament用 2.39:1（シネマスコープ）
          }
        end

        # バリアント画像が無いか古ければ生成。
        # 生成物はソースの隣ではなく生成キャッシュ .cache/vs/theme-images/ へ
        # （名前は ThemeImageResolver.cache_stem・generated-assets 移設仕様 §2）。
        # waifu2x を伴う高コスト処理のため、生成済みチェックが実質のメモ化になる。
        # 元画像を描き直したときと、判型が変わって扉絵の縦横比が合わなくなったときは作り直す。
        # @param source_path [String] ThemeImageResolver が見つけた元画像
        def ensure_variant_generated(source_path, variant)
          discard_outdated_variants!
          stem = ThemeImageResolver.cache_stem(source_path)
          target = File.join(ThemeImageResolver.theme_images_cache_root, "#{stem}_#{variant}.webp")
          return target if File.exist?(target) && ThemeImageResolver.cached_variant_current?(target, variant)

          success = generate_frontispiece_and_ornament_from(source_path)
          success ? target : nil
        end

        # frontispiece と ornament を生成
        # @param source_path [String] 元画像（本のルートからの相対か、絶対パス）
        def generate_frontispiece_and_ornament_from(source_path, fuzz: nil, waifu2x: DEFAULT_WAIFU2X_BIN,
                                                    waifu2x_args: [], waifu2x_noise: FRONTISPIECE_WAIFU2X_NOISE,
                                                    scale: FRONTISPIECE_SCALE, target_width: FRONTISPIECE_TARGET_WIDTH,
                                                    webp_quality: FRONTISPIECE_WEBP_QUALITY, keep_intermediate: false)
          ensure_magick_available!

          raise "画像が見つかりません: #{source_path}" unless File.file?(source_path)

          basename = File.basename(source_path, '.*')

          # 出力先はソースの隣ではなく生成キャッシュ（名前は ThemeImageResolver.cache_stem・移設仕様 §2）。
          # themes/standard/images/sakura.webp → theme-images/themes/standard/images/、
          # stylesheets/images/myphoto.png → theme-images/ 直下。
          base_dir = File.dirname(File.join(ThemeImageResolver.theme_images_cache_root,
                                            ThemeImageResolver.cache_stem(source_path)))

          Common.log_action("frontispiece/ornament 生成: #{ThemeImageResolver.book_relative(source_path)} → " \
                            "#{basename}_portrait/landscape.webp")

          waifu2x_available = waifu2x && !waifu2x.strip.empty? && Common.external_command_available?(waifu2x)
          warned_missing_waifu2x = false

          Dir.mktmpdir('frontispiece-one') do |tmpdir|
            trimmed_path = File.join(tmpdir, "#{basename}_trimmed.png")
            trim_image_to(source_path, trimmed_path, fuzz)

            frontispiece_variants.each do |variant, ratio|
              variant_png = File.join(tmpdir, "#{basename}_#{variant}.png")
              generate_diagonal_variant(trimmed_path, variant_png, ratio)

              # 拡大が要る小さい絵だけ waifu2x を通す。要るのに無いときだけ警告する（十分に
              # 大きい絵なら、waifu2x が無くても仕上がりは同じなので知らせない）
              upscale = needs_waifu2x?(variant_png, target_width)
              if upscale && !waifu2x_available && !warned_missing_waifu2x
                Common.log_warn("waifu2x (#{waifu2x}) が見つかりません。ImageMagick のみで生成します。")
                warned_missing_waifu2x = true
              end

              target_path = File.join(base_dir, "#{basename}_#{variant}.webp")
              generate_variant_output(
                variant_png,
                target_path,
                variant: variant,
                waifu2x_available: upscale && waifu2x_available,
                waifu2x: waifu2x,
                waifu2x_args: waifu2x_args,
                waifu2x_noise: waifu2x_noise,
                scale: scale,
                target_width: target_width,
                webp_quality: webp_quality,
                keep_intermediate: keep_intermediate
              )

              Common.log_success("生成しました: #{target_path}")
            end
          end

          true
        rescue StandardError => e
          Common.log_error("frontispiece/ornament 生成に失敗しました: #{e.message}")
          false
        end

        # 並べ直した絵が、仕上がりの幅に対して waifu2x で拡大するほど小さいか（改善案 #143）。
        # 寸法が読めなければ、今までどおり拡大する側に倒す
        def needs_waifu2x?(variant_png, target_width)
          width, = Common.image_size(variant_png)
          width.nil? || width < target_width * WAIFU2X_SKIP_WIDTH_RATIO
        end

        # ImageMagick が利用可能かチェック
        def ensure_magick_available!
          _out, status = Open3.capture2('magick', '-version')
          raise 'ImageMagick (magick) が見つかりません。インストールを確認してください。' unless status.success?
        rescue Errno::ENOENT
          raise 'magick コマンドが見つかりません。ImageMagick をインストールしてください。'
        end

        # 画像をトリミング
        def trim_image_to(source_path, destination_path, fuzz)
          FileUtils.mkdir_p(File.dirname(destination_path))
          command = ['magick', source_path, '-alpha', 'set']
          command += ['-fuzz', fuzz] if fuzz
          command += ['-bordercolor', 'none', '-border', '1x1', '-trim', '+repage', "PNG32:#{destination_path}"]
          run_command!(command, label: "トリミング (#{File.basename(source_path)})")
        end

        # 対角線分割バリアントを生成
        def generate_diagonal_variant(input_png, output_png, ratio)
          width, height = Common.image_size(input_png)
          raise "寸法取得に失敗しました: #{input_png}" unless width

          ratio = ratio.to_f
          current_ratio = height.to_f / width
          if ratio >= current_ratio
            new_width = width
            new_height = (width * ratio).round
            bottom_x_offset = 0
            bottom_y_offset = new_height - height
          else
            new_height = height
            new_width = (height / ratio).round
            bottom_x_offset = new_width - width
            bottom_y_offset = 0
          end

          top_path = output_png.sub(/\.png\z/, '_top.png')
          bottom_path = output_png.sub(/\.png\z/, '_bottom.png')

          # 透過は透過のまま運ぶ（改善案 #140）。白で塗ってから白を抜くと、絵の中の白
          # （白い花びら）まで透明になり、半透明の縁は白く塗られて不透明に残る。
          # 三角形は元の絵のアルファに三角形の形を掛けて切り出す（DstIn）。
          top_cmd = [
            'magick', input_png,
            '(', '-size', "#{width}x#{height}", 'xc:none', '-fill', 'white', '-draw', "polygon 0,0 #{width},0 0,#{height}", ')',
            '-compose', 'DstIn', '-composite', "PNG32:#{top_path}"
          ]
          bottom_cmd = [
            'magick', input_png,
            '(', '-size', "#{width}x#{height}", 'xc:none', '-fill', 'white', '-draw', "polygon #{width},#{height} #{width},0 0,#{height}", ')',
            '-compose', 'DstIn', '-composite', "PNG32:#{bottom_path}"
          ]
          composite_cmd = [
            'magick',
            '-size', "#{new_width}x#{new_height}",
            'xc:none',
            '+repage',
            top_path, '-geometry', '+0+0', '-compose', 'Over', '-composite',
            bottom_path, '-geometry', "+#{bottom_x_offset}+#{bottom_y_offset}", '-compose', 'Over', '-composite',
            "PNG32:#{output_png}"
          ]

          run_command!(top_cmd, label: '対角線分割 (上)')
          run_command!(bottom_cmd, label: '対角線分割 (下)')
          run_command!(composite_cmd, label: '対角線分割 (合成)')
        ensure
          FileUtils.rm_f(top_path)
          FileUtils.rm_f(bottom_path)
        end

        # バリアント出力を生成
        # rubocop:disable Lint/UnusedMethodArgument
        def generate_variant_output(input_png, target_path, variant:, waifu2x_available:, waifu2x:, waifu2x_args:,
                                    waifu2x_noise:, scale:, target_width:, webp_quality:, keep_intermediate:)
          # rubocop:enable Lint/UnusedMethodArgument
          FileUtils.mkdir_p(File.dirname(target_path))

          variant_label = File.basename(target_path)

          unless waifu2x_available
            convert_to_webp(input_png, target_path, target_width:, webp_quality:, label: variant_label)
            return
          end

          # waifu2x 経路: アルファ抽出 → waifu2x 拡大 → アルファ拡大 → 再合成 の中間 PNG は
          # tmpdir に隔離する。base_dir（bundled/）へ書かないため、途中で例外が起きても
          # ブロック離脱で自動削除され、bundled/ に中間生成物が残らない。
          Dir.mktmpdir('frontispiece-variant') do |tmpdir|
            stem              = File.join(tmpdir, File.basename(target_path, '.webp'))
            alpha_path        = "#{stem}_alpha.png"
            alpha_scaled_path = "#{stem}_alpha_x#{scale}.png"
            color_path        = "#{stem}_color_x#{scale}.png"
            merged_path       = "#{stem}_merged_x#{scale}.png"

            run_command!(
              ['magick', input_png, '-alpha', 'extract', "PNG32:#{alpha_path}"],
              label: "アルファ抽出 (#{variant_label})"
            )

            waifu_cmd = [waifu2x, '-i', input_png, '-o', color_path, '-n', waifu2x_noise.to_s, '-s',
                         scale.to_s] + waifu2x_args
            run_command!(
              waifu_cmd,
              label: "waifu2x (#{variant_label})",
              stream_output: Common.current_log_level >= 3
            )

            scale_percent = format('%.2f%%', scale.to_f * 100)
            run_command!(
              ['magick', alpha_path, '-filter', 'catrom', '-resize', scale_percent, "PNG32:#{alpha_scaled_path}"],
              label: "アルファ拡大 (#{variant_label})"
            )

            # alpha_scaled_path は PNG32 で書いたので、不透明のアルファを持つ。CopyAlpha は
            # 重ねる画像にアルファがあるとそれを写すため、外して濃淡を透過として写す。
            run_command!(
              ['magick', color_path, '(', alpha_scaled_path, '-alpha', 'off', ')',
               '-compose', 'CopyAlpha', '-composite', "PNG32:#{merged_path}"],
              label: "アルファ再適用 (#{variant_label})"
            )

            convert_to_webp(merged_path, target_path, target_width:, webp_quality:, label: variant_label)
          end
        end

        # 画像（PNG 等）を最終的な WebP（透過・指定幅・品質）へ変換して target_path に書き出す。
        # 白を透過にはしない（絵の中の白まで抜ける・改善案 #140）。透過は入力のアルファのまま。
        def convert_to_webp(source_path, target_path, target_width:, webp_quality:, label:)
          convert_cmd = [
            'magick', source_path,
            '-alpha', 'set',
            '-background', 'none',
            '-resize', "#{target_width}x",
            '-quality', webp_quality.to_s,
            target_path
          ]
          run_command!(convert_cmd, label: "WebP 変換 (#{label})")
        end

        # コマンドを実行
        def run_command!(cmd, label:, stream_output: false)
          Common.log_action("  $ #{Shellwords.join(cmd.map(&:to_s))}")

          if stream_output
            # stderr は常に /dev/null へ捨てる（waifu2x-ncnn-vulkan 等のデバイス情報ログを抑制）
            success = system(*cmd, err: File::NULL)
            raise "#{label} に失敗しました" unless success

            return
          end

          # stderr は /dev/null へ捨てる。エラー時のみ再取得して報告する
          stdout_str, status = Open3.capture2(*cmd, err: File::NULL)

          if status.success?
            if Common.current_log_level >= 3 && stdout_str && !stdout_str.strip.empty?
              stdout_str.each_line { |line| Common.log_debug("#{label}: #{line.rstrip}") }
            end
            return
          end

          # 失敗時は stderr も取得してエラーメッセージに含める
          _out, stderr_str, = Open3.capture3(*cmd)
          combined = [stdout_str, stderr_str].map(&:to_s).reject(&:empty?).join("\n")
          message = combined.empty? ? "#{label} に失敗しました" : "#{label} に失敗しました:\n#{combined}"
          raise message
        end
      end
    end
  end
end
