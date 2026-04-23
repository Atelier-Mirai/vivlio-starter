# ブラウン運動のシミュレーション
# 液体中の花粉粒子がランダムに動く様子を再現する
# アインシュタイン, 1905年

# ブラウン運動の軌跡を生成する
# 各ステップでランダムな方向に delta だけ移動する2次元ランダムウォーク
# @param steps [Integer] シミュレーションのステップ数
# @param delta [Float] 1ステップあたりの移動距離（デフォルト: 1.0）
# @return [Array<Array<Float>>] 各ステップの座標 [[x, y], ...] の配列
def brownian_motion(steps:, delta: 1.0)
  x, y = 0.0, 0.0
  trajectory = [[x, y]]

  steps.times do
    angle = rand * 2 * Math::PI
    x += delta * Math.cos(angle)
    y += delta * Math.sin(angle)
    trajectory << [x.round(4), y.round(4)]
  end

  trajectory
end

# 軌跡の平均二乗変位（MSD）を計算する
# MSD は粒子の拡散の広がりを示す指標で、ステップ数に比例して増加する
# @param trajectory [Array<Array<Float>>] brownian_motion が返す座標の配列
# @return [Float] 平均二乗変位
def mean_square_displacement(trajectory)
  trajectory.map { |x, y| x**2 + y**2 }.sum / trajectory.size
end

# 100ステップのブラウン運動を3粒子分シミュレート
puts "ブラウン運動シミュレーション（100ステップ）"
3.times do |i|
  path = brownian_motion(steps: 100)
  msd  = mean_square_displacement(path)
  last = path.last
  puts "  粒子#{i + 1}: 終点 (#{last[0]}, #{last[1]}), 平均二乗変位 = #{msd.round(4)}"
end
