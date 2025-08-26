# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# 合成版: flower.png を黄化、frame.png を緑/紫へ色相回転し、合成して frame-<name>.webp を生成
namespace :frames do
  desc 'Compose frames by hue-rotating flower.png (to yellow) and frame.png (to green/purple). Usage: rake "frames:compose[green]"'
  task :compose, [:target] do |_, args|
    # ImageMagick コマンド検出
    magick = ENV['MAGICK']
    if magick.nil? || magick.strip.empty?
      magick = `command -v magick`.strip
      if magick.nil? || magick.empty?
        alt = `command -v convert`.strip
        if alt.nil? || alt.empty?
          abort 'ImageMagick not found. Install it or set MAGICK=/path/to/magick'
        else
          magick = 'convert'
        end
      end
    end

    img_dir = ENV['IMGDIR'] || 'stylesheets/images'
    flower_src = ENV['FLOWER'] || File.join(img_dir, 'flower.png')
    frame_src  = ENV['FRAME']  || File.join(img_dir, 'frame.png')
    outdir     = ENV['OUTDIR'] || img_dir

    # Hue rotation parameters
    # You can pass degrees via *_DEG (e.g., H_FRAME_GREEN_DEG=-120), or direct percent via H_* (0..200; 100=no change)
    to_pct = lambda do |deg|
      pct = 100.0 + (deg.to_f / 180.0) * 100.0
      [[pct, 0.0].max, 200.0].min.round(2)
    end

    # Sensible defaults assuming source is blue (~240°):
    #  - flower to yellow: +180° -> 200%
    #  - frame to green:  -120° -> ~33%
    #  - frame to purple:  +60° -> ~133%
    h_flower_yellow = (
      if ENV['H_FLOWER_YELLOW_DEG']
        to_pct.call(ENV['H_FLOWER_YELLOW_DEG'])
      else
        ENV['H_FLOWER_YELLOW'] || '200'
      end
    ).to_s
    h_frame_green = (
      if ENV['H_FRAME_GREEN_DEG']
        to_pct.call(ENV['H_FRAME_GREEN_DEG'])
      else
        ENV['H_FRAME_GREEN'] || '33'
      end
    ).to_s
    h_frame_purple = (
      if ENV['H_FRAME_PURPLE_DEG']
        to_pct.call(ENV['H_FRAME_PURPLE_DEG'])
      else
        ENV['H_FRAME_PURPLE'] || '133'
      end
    ).to_s

    # Optional saturation/brightness
    sat = (ENV['SAT'] || '100').to_s
    bri = (ENV['BRI'] || '100').to_s

    gravity = ENV['GRAVITY'] || 'center'
    compose_mode = ENV['COMPOSE_MODE'] || 'over' # e.g., over, multiply, screen
    compose_order = (ENV['COMPOSE_ORDER'] || 'frame_under').to_s # 'frame_under' or 'flower_under'

    # Background removal (make white transparent)
    bg_color = ENV['BG_COLOR'] || 'white'
    bg_fuzz  = ENV['BG_FUZZ']  || '2%'

    targets = case (args[:target] || 'all').to_s
              when 'green'  then %w[green]
              when 'purple' then %w[purple]
              else %w[green purple]
              end

    FileUtils.mkdir_p(outdir) unless Dir.exist?(outdir)

    tmp = Dir.mktmpdir('frames-compose')
    begin
      # 入力はいずれも 2200x650 のためリサイズ不要。PNG32で正規化のみ行う。
      frame_base = File.join(tmp, 'frame-base.png')
      system(%Q(#{magick} "#{frame_src}" -alpha on -fuzz #{bg_fuzz} -transparent #{bg_color} PNG32:"#{frame_base}")) || abort('Failed to read frame.png')

      flower_fit = File.join(tmp, 'flower-fit.png')
      system(%Q(#{magick} "#{flower_src}" -alpha on -fuzz #{bg_fuzz} -transparent #{bg_color} PNG32:"#{flower_fit}")) || abort('Failed to read flower.png')

      targets.each do |name|
        # 花: 既定は回転しない（透過化済みの元画像を使用）。
        # 環境変数 FLOWER_HUE_ENABLED=1 のときのみ以前の黄色化を適用。
        flower_out = if ENV['FLOWER_HUE_ENABLED'] == '1'
          out = File.join(tmp, 'flower-colored.png')
          system(%Q(#{magick} "#{flower_fit}" -modulate #{bri},#{sat},#{h_flower_yellow} PNG32:"#{out}")) || abort('Flower hue rotation failed')
          out
        else
          flower_fit
        end

        # 枠→対象色
        frame_out = File.join(tmp, "frame-#{name}.png")
        hue = (name == 'green') ? h_frame_green : h_frame_purple
        system(%Q(#{magick} "#{frame_base}" -modulate #{bri},#{sat},#{hue} PNG32:"#{frame_out}")) || abort('Frame hue rotation failed')

        # 合成: 既定は 枠（下） + 花（上）
        composed = File.join(outdir, "frame-#{name}.webp")
        cmd = if compose_order == 'flower_under'
          %Q(#{magick} -background none "#{flower_out}" "#{frame_out}" -gravity #{gravity} -compose #{compose_mode} -composite -define webp:lossless=true "#{composed}")
        else
          %Q(#{magick} -background none "#{frame_out}" "#{flower_out}" -gravity #{gravity} -compose #{compose_mode} -composite -define webp:lossless=true "#{composed}")
        end
        ok = system(cmd)
        abort('Compositing failed') unless ok
        puts "Composed #{composed}"
      end
    ensure
      FileUtils.remove_entry(tmp) if tmp && Dir.exist?(tmp)
    end
  end
end
