require 'vips'

class IllustrationExtractor
  MIN_HEIGHT     = 100
  MIN_WIDTH      = 100
  ASPECT_MAX     = 5.0
  BG_THRESHOLD   = 210   # これ以下を「非白」とみなす
  SMOOTH_SIGMA   = 10    # 行密度の平滑化
  MAX_GAP        = 30    # 許容ギャップ行数

  def initialize(input_path)
    @input_path = input_path
    @source     = Vips::Image.new_from_file(input_path)
    @img_w      = @source.width
    @img_h      = @source.height
    puts "画像サイズ: #{@img_w} x #{@img_h}"
  end

  def extract(output_dir: "output", prefix: "illust")
    Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

    # グレースケール化
    gray = @source.colourspace("b-w")

    # ✅ Sobelではなく「白背景との差分」で非白領域を検出
    # BG_THRESHOLD 以下のピクセルを前景とみなす
    fg_mask = gray
      .relational_const(:less, [BG_THRESHOLD])
      .cast(:uchar)
      .linear([255.0], [0])
      .cast(:uchar)

    # デバッグ保存
    fg_mask.write_to_file(File.join(output_dir, "debug_fg.png"))

    # 行ごとの前景ピクセル密度を計算
    row_scores = (0...@img_h).map do |y|
      fg_mask.crop(0, y, @img_w, 1).avg / 255.0
    end

    # ガウス平滑化（隣接行のノイズを吸収）
    smoothed = gaussian_smooth(row_scores, sigma: 10)

    avg = smoothed.sum / smoothed.size
    std = Math.sqrt(smoothed.map { |v| (v - avg)**2 }.sum / smoothed.size)

    # ✅ 閾値を実測値から自動計算（平均 + 0.5*標準偏差）
    threshold = avg + std * 0.5
    puts "  行密度 avg=#{avg.round(4)} std=#{std.round(4)} threshold=#{threshold.round(4)}"

    groups = find_groups(smoothed, threshold)
    puts "  グループ数: #{groups.size}"

    if groups.empty?
      puts "イラスト領域が見つかりませんでした"
      return []
    end

    groups.each_with_index.filter_map do |g, i|
      save_region(g, i, fg_mask, output_dir, prefix)
    end
  end

  private

  # 簡易ガウス平滑化（移動平均で近似）
  def gaussian_smooth(scores, sigma:)
    radius = (sigma * 2).to_i
    result = scores.dup
    scores.each_with_index do |_, y|
      weights = []
      values  = []
      (-radius..radius).each do |dy|
        ny = y + dy
        next if ny < 0 || ny >= scores.size
        w = Math.exp(-(dy**2) / (2.0 * sigma**2))
        weights << w
        values  << scores[ny] * w
      end
      result[y] = values.sum / weights.sum
    end
    result
  end

  def find_groups(scores, threshold)
    groups  = []
    start_y = nil
    gap     = 0

    scores.each_with_index do |score, y|
      if score >= threshold
        start_y ||= y
        gap = 0
      elsif start_y
        gap += 1
        if gap > MAX_GAP
          end_y  = y - gap
          height = end_y - start_y
          groups << { y: start_y, height: height } if height >= MIN_HEIGHT
          start_y = nil
          gap     = 0
        end
      end
    end

    if start_y && (@img_h - start_y) >= MIN_HEIGHT
      groups << { y: start_y, height: @img_h - start_y }
    end

    groups
  end

  def save_region(group, index, fg_mask, output_dir, prefix)
    y = group[:y]
    h = group[:height]

    # x方向も前景密度でトリム
    col_scores = (0...@img_w).map do |x|
      fg_mask.crop(x, y, 1, h).avg / 255.0
    end

    active_cols = col_scores.each_with_index.select { |v, _| v > 0.05 }.map { |_, x| x }
    return nil if active_cols.empty?

    margin = 8
    x1 = [active_cols.min - margin, 0].max
    x2 = [active_cols.max + margin, @img_w].min
    w  = x2 - x1
    y1 = [y - margin, 0].max
    y2 = [y + h + margin, @img_h].min
    rh = y2 - y1

    return nil if w < MIN_WIDTH
    aspect = w.to_f / rh
    return nil if aspect > ASPECT_MAX

    out_path = File.join(output_dir, "#{prefix}_%02d.png" % index)
    @source.crop(x1, y1, w, rh).write_to_file(out_path)

    puts "  [#{index}] 保存: #{out_path} (x:#{x1} y:#{y1} w:#{w} h:#{rh} aspect:#{aspect.round(2)})"
    out_path
  rescue Vips::Error => e
    puts "  [#{index}] 保存失敗: #{e.message}"
    nil
  end
end

if $PROGRAM_NAME == __FILE__
  input_path = ARGV[0] || "/Users/mirai/projects/vivlio-starter/sources/three-elements-ocr4.png"
  output_dir = ARGV[1] || "/tmp/illustration-experiment"

  extractor = IllustrationExtractor.new(input_path)
  saved = extractor.extract(output_dir:, prefix: "illust")
  puts "\n#{saved.size} 件保存完了 (#{output_dir})"
end
# ```

# ## 変更の核心
# ```
# ❌ 従来: Sobel → gaussblur → 二値化
#          vips内部で値が正規化されてmax=83止まり
#          → 閾値との整合が取れずマスクが真っ白

# ✅ 新方式: 白背景との直接比較
#          gray < 210 → 非白領域を前景とみなす
#          → Sobelの値域問題を完全に回避
#          → 閾値も実測avg+stdで自動計算