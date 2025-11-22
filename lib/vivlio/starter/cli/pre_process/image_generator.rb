# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'tmpdir'
require 'shellwords'
require_relative '../common'
require_relative 'theme_image_resolver'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # 画像生成処理を担当するモジュール（waifu2x連携、ImageMagick操作）
        module ImageGenerator
          DEFAULT_WAIFU2X_BIN = File.expand_path('~/.local/bin/waifu2x/waifu2x-ncnn-vulkan')
          FRONTISPIECE_WAIFU2X_NOISE = 1
          FRONTISPIECE_SCALE = 2
          FRONTISPIECE_TARGET_WIDTH = 2880  # frontispiece推奨横幅
          FRONTISPIECE_WEBP_QUALITY = 90

          module_function

          def frontispiece_variants
            portrait_ratio = ThemeImageResolver.binding_safe_portrait_ratio
            {
              portrait: portrait_ratio,
              landscape: (1.0 / 2.39) # ornament用 2.39:1（シネマスコープ）
            }
          end

          # バリアント画像が存在しなければ生成
          def ensure_variant_generated(source_path, variant)
            images_root = ThemeImageResolver.theme_images_root
            relative = source_path.sub(%r{\A#{Regexp.escape(images_root)}/}, '')
            return nil if relative.empty?

            base = relative.sub(/\.[^.]+\z/, '')
            target = File.join(images_root, "#{base}_#{variant}.webp")
            return target if File.exist?(target)

            spec = relative
            success = generate_frontispiece_and_ornament_from(spec)
            success ? target : nil
          end

          # frontispiece と ornament を生成
          def generate_frontispiece_and_ornament_from(image_spec, fuzz: nil, waifu2x: DEFAULT_WAIFU2X_BIN,
                                                      waifu2x_args: [], waifu2x_noise: FRONTISPIECE_WAIFU2X_NOISE,
                                                      scale: FRONTISPIECE_SCALE, target_width: FRONTISPIECE_TARGET_WIDTH,
                                                      webp_quality: FRONTISPIECE_WEBP_QUALITY, keep_intermediate: false)
            ensure_magick_available!

            images_root = File.join(Common::STYLESHEETS_DIR, 'images')
            source_path = resolve_image_reference(images_root, image_spec)
            base_dir = File.dirname(source_path)
            basename = File.basename(source_path, '.*')

            Common.log_action("frontispiece/ornament 生成: #{image_spec} → #{basename}_portrait/landscape.webp")

            waifu2x_available = waifu2x && !waifu2x.strip.empty? && command_available?(waifu2x)
            unless waifu2x_available
              Common.log_warn("waifu2x (#{waifu2x}) が見つかりません。ImageMagick のみで生成します。")
            end

            Dir.mktmpdir('frontispiece-one') do |tmpdir|
              trimmed_path = File.join(tmpdir, "#{basename}_trimmed.png")
              trim_image_to(source_path, trimmed_path, fuzz)

              frontispiece_variants.each do |variant, ratio|
                variant_png = File.join(tmpdir, "#{basename}_#{variant}.png")
                generate_diagonal_variant(trimmed_path, variant_png, ratio)

                target_path = File.join(base_dir, "#{basename}_#{variant}.webp")
                generate_variant_output(
                  variant_png,
                  target_path,
                  variant: variant,
                  waifu2x_available: waifu2x_available,
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

          # ImageMagick が利用可能かチェック
          def ensure_magick_available!
            _out, status = Open3.capture2('magick', '-version')
            raise 'ImageMagick (magick) が見つかりません。インストールを確認してください。' unless status.success?
          rescue Errno::ENOENT
            raise 'magick コマンドが見つかりません。ImageMagick をインストールしてください。'
          end

          # コマンドが利用可能かチェック
          def command_available?(cmd)
            return File.executable?(cmd) if cmd.include?(File::SEPARATOR)

            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
              candidate = File.join(path, cmd)
              File.executable?(candidate)
            end
          end

          # 画像参照を解決
          def resolve_image_reference(images_root, image_spec)
            spec = image_spec.to_s.strip
            raise '画像指定が空です' if spec.empty?

            normalized_root = File.expand_path(images_root)
            base_dir = normalized_root.end_with?(File::SEPARATOR) ? normalized_root : normalized_root + File::SEPARATOR
            relative = spec.sub(%r{^/+}, '')
            absolute = File.expand_path(relative, base_dir)

            unless absolute == normalized_root || absolute.start_with?(normalized_root + File::SEPARATOR)
              raise "画像指定が不正です: #{spec}"
            end

            return absolute if File.exist?(absolute)

            if File.extname(relative).empty?
              %w[.webp .png .jpg .jpeg].each do |ext|
                candidate = absolute + ext
                return candidate if File.exist?(candidate)
              end
            else
              stem = absolute.sub(/\.[^.]+\z/, '')
              exts = %w[.webp .png .jpg .jpeg]
              ([absolute] + exts.map { |ext| "#{stem}#{ext}" }).each do |candidate|
                return candidate if File.exist?(candidate)
              end
            end

            raise "画像が見つかりません: #{spec}"
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
            dims, status = Open3.capture2('magick', 'identify', '-format', '%w %h', input_png)
            raise "寸法取得に失敗しました: #{input_png}" unless status.success?

            width_str, height_str = dims.strip.split
            width = width_str.to_i
            height = height_str.to_i
            raise "不正な寸法です: #{input_png}" if width <= 0 || height <= 0

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

            top_cmd = [
              'magick', input_png,
              '-background', 'white', '-flatten',
              '(', '-size', "#{width}x#{height}", 'xc:none', '-fill', 'white', '-draw', "polygon 0,0 #{width},0 0,#{height}", ')',
              '-compose', 'CopyAlpha', '-composite', "PNG32:#{top_path}"
            ]
            bottom_cmd = [
              'magick', input_png,
              '-background', 'white', '-flatten',
              '(', '-size', "#{width}x#{height}", 'xc:none', '-fill', 'white', '-draw', "polygon #{width},#{height} #{width},0 0,#{height}", ')',
              '-compose', 'CopyAlpha', '-composite', "PNG32:#{bottom_path}"
            ]
            composite_cmd = [
              'magick',
              '-size', "#{new_width}x#{new_height}",
              'xc:white',
              '-alpha', 'set',
              '+repage',
              top_path, '-geometry', "+0+0", '-compose', 'Over', '-composite',
              bottom_path, '-geometry', "+#{bottom_x_offset}+#{bottom_y_offset}", '-compose', 'Over', '-composite',
              '-transparent', 'white',
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
          def generate_variant_output(input_png, target_path, variant:, waifu2x_available:, waifu2x:, waifu2x_args:,
                                       waifu2x_noise:, scale:, target_width:, webp_quality:, keep_intermediate:)
            FileUtils.mkdir_p(File.dirname(target_path))

            variant_label = File.basename(target_path)

            if waifu2x_available
              alpha_path = target_path.sub(/\.webp\z/, '_alpha.png')
              alpha_scaled_path = target_path.sub(/\.webp\z/, "_alpha_x#{scale}.png")
              color_path = target_path.sub(/\.webp\z/, "_color_x#{scale}.png")
              merged_path = target_path.sub(/\.webp\z/, "_merged_x#{scale}.png")

              run_command!(
                ['magick', input_png, '-alpha', 'extract', "PNG32:#{alpha_path}"],
                label: "アルファ抽出 (#{variant_label})"
              )

              waifu_cmd = [waifu2x, '-i', input_png, '-o', color_path, '-n', waifu2x_noise.to_s, '-s', scale.to_s] + waifu2x_args
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

              run_command!(
                ['magick', color_path, alpha_scaled_path, '-compose', 'CopyAlpha', '-composite', "PNG32:#{merged_path}"],
                label: "アルファ再適用 (#{variant_label})"
              )

              source_for_webp = merged_path
            else
              source_for_webp = input_png
              alpha_path = alpha_scaled_path = color_path = merged_path = nil
            end

            convert_cmd = [
              'magick', source_for_webp,
              '-alpha', 'set',
              '-background', 'none',
              '-transparent', 'white',
              '-resize', "#{target_width}x",
              '-quality', webp_quality.to_s,
              target_path
            ]
            run_command!(convert_cmd, label: "WebP 変換 (#{variant_label})")

            unless keep_intermediate
              [alpha_path, alpha_scaled_path, color_path, merged_path].compact.each { |path| FileUtils.rm_f(path) }
            end
          end

          # コマンドを実行
          def run_command!(cmd, label:, stream_output: false)
            Common.log_action("  $ #{Shellwords.join(cmd.map(&:to_s))}")

            if stream_output
              success = system(*cmd)
              raise "#{label} に失敗しました" unless success
              return
            end

            stdout_str, stderr_str, status = Open3.capture3(*cmd)

            if status.success?
              if Common.current_log_level >= 3
                [stdout_str, stderr_str].each do |chunk|
                  next if chunk.nil? || chunk.strip.empty?
                  chunk.each_line { |line| Common.log_debug("#{label}: #{line.rstrip}") }
                end
              end
              return
            end

            combined = [stdout_str, stderr_str].map(&:to_s).reject(&:empty?).join("\n")
            message = combined.empty? ? "#{label} に失敗しました" : "#{label} に失敗しました:\n#{combined}"
            raise message
          end
        end
      end
    end
  end
end
