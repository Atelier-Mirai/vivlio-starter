# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# フレーム画像（frame-<theme>.webp）を再生成する Rake タスク
# - 使い方例:
#   - rake "frames:generate[green]"
#   - rake "frames:generate[purple]"
#   - rake frames:generate               # 両方生成（既定）
# - 環境変数で調整可能:
#   - MAGICK: ImageMagick のコマンドパス（既定は自動検出: `magick` → `convert`）
#   - SRC: 入力画像（既定: stylesheets/images/frame-yellow.webp）
#   - OUTDIR: 出力ディレクトリ（既定: stylesheets/images）
#   - FUZZ_MAIN / FUZZ_SEC: 近傍色の許容率（既定: 18% / 10%）
#   - FLOWER_GREEN / BORDER_GREEN / FLOWER_PURPLE / BORDER_PURPLE: 出力色
#   - SRC_FLOWER_MAIN / SRC_FLOWER_SUB / SRC_BORDER_MAIN / SRC_BORDER_SUB: 置換元の黄色系代表色
#
# 置換手順:
#  1) 花（明るい黄）を目的色へ置換（2色）
#  2) 枠（やや暗い黄）を目的色へ置換（2色）
#  テクスチャ保持のため -opaque のみで色置換しています。

namespace :frames do
  desc 'Generate themed frame images (green/purple/all). Usage: rake "frames:generate[green]"'
  task :generate, [:target] do |_, args|
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

    src = ENV['SRC'] || 'stylesheets/images/frame-yellow.webp'
    outdir = ENV['OUTDIR'] || 'stylesheets/images'

    fuzz_main = ENV['FUZZ_MAIN'] || '18%'
    fuzz_sec  = ENV['FUZZ_SEC']  || '10%'
    # 枠専用の fuzz（未指定なら共通の値を使用）
    border_fuzz_main = ENV['BORDER_FUZZ_MAIN'] || fuzz_main
    border_fuzz_sec  = ENV['BORDER_FUZZ_SEC']  || fuzz_sec

    skip_flower   = (ENV['SKIP_FLOWER'].to_s == '1')
    skip_border   = (ENV['SKIP_BORDER'].to_s == '1')
    protect_flower = (ENV['PROTECT_FLOWER'].to_s == '1') # SKIP_FLOWER=1 の時に花色を保護する（既定: ON 相当で後段ロジックで判定）

    colors = {
      'green' => {
        flower: ENV['FLOWER_GREEN']  || '#3cb371',
        border: ENV['BORDER_GREEN']  || '#2e8b57'
      },
      'purple' => {
        flower: ENV['FLOWER_PURPLE'] || '#7d4aa6',
        border: ENV['BORDER_PURPLE'] || '#65408a'
      }
    }

    base_colors = {
      flower_main: ENV['SRC_FLOWER_MAIN']  || '#f0a000',
      flower_sub:  ENV['SRC_FLOWER_SUB']   || '#f3b200',
      border_main: ENV['SRC_BORDER_MAIN']  || '#b47a00',
      border_sub:  ENV['SRC_BORDER_SUB']   || '#9c6a00'
    }

    # 枠の追加置換元色（カンマ区切り）。未指定なら代表的な黄〜橙系をデフォルトで補足
    border_extra = (ENV['SRC_BORDER_EXTRA'] || '#c88a00,#a87200,#8a5f00,#d39c00,#e0a800')
                    .split(',')
                    .map { |s| s.strip }
                    .reject(&:empty?)

    targets = case (args[:target] || 'all').to_s
              when 'green'  then %w[green]
              when 'purple' then %w[purple]
              else %w[green purple]
              end

    FileUtils.mkdir_p(outdir) unless Dir.exist?(outdir)

    sh = lambda do |cmd|
      puts cmd
      ok = system(cmd)
      abort("Command failed: #{cmd}") unless ok
    end

    targets.each do |name|
      out = File.join(outdir, "frame-#{name}.webp")
      c = colors.fetch(name)

      if skip_flower
        # 花の置換をスキップする場合は src をそのまま out にコピーして開始
        FileUtils.cp(src, out)
      else
        # 花の色を置換（src -> out）
        cmd1 = %Q(#{magick} #{src} \
          -fuzz #{fuzz_main} -fill "#{c[:flower]}" -opaque "#{base_colors[:flower_main]}" \
          -fuzz #{fuzz_sec}  -fill "#{c[:flower]}" -opaque "#{base_colors[:flower_sub]}" \
          #{out})
        sh.call(cmd1)
      end

      unless skip_border
        # 花を保護する場合は、先に花の代表色2種をセンチネル色に一時退避
        # センチネル色は画像内に存在しにくい原色系を使用
        sentinel1 = '#ff00ff' # for flower_main
        sentinel2 = '#00ffff' # for flower_sub

        if skip_flower && (protect_flower || ENV['PROTECT_FLOWER'].nil?)
          cmd_protect = %Q(#{magick} #{out} \
            -fuzz #{fuzz_main} -fill "#{sentinel1}" -opaque "#{base_colors[:flower_main]}" \
            -fuzz #{fuzz_sec}  -fill "#{sentinel2}" -opaque "#{base_colors[:flower_sub]}" \
            #{out})
          sh.call(cmd_protect)
        end

        # 枠の色を置換（out 上書き）。代表色2つ + 追加色リストを順に適用
        cmd2 = %Q(#{magick} #{out} \
          -fuzz #{border_fuzz_main} -fill "#{c[:border]}" -opaque "#{base_colors[:border_main]}" \
          -fuzz #{border_fuzz_sec}  -fill "#{c[:border]}" -opaque "#{base_colors[:border_sub]}" \
          #{out})
        sh.call(cmd2)

        border_extra.each do |hex|
          next if hex.empty?
          cmd_extra = %Q(#{magick} #{out} \
            -fuzz #{border_fuzz_sec} -fill "#{c[:border]}" -opaque "#{hex}" \
            #{out})
          sh.call(cmd_extra)
        end

        # 花色を元に戻す（センチネル→元の黄）
        if skip_flower && (protect_flower || ENV['PROTECT_FLOWER'].nil?)
          cmd_restore = %Q(#{magick} #{out} \
            -fill "#{base_colors[:flower_main]}" -opaque "#{sentinel1}" \
            -fill "#{base_colors[:flower_sub]}"  -opaque "#{sentinel2}" \
            #{out})
          sh.call(cmd_restore)
        end
      end

      puts "Generated #{out}"
    end
  end
end
