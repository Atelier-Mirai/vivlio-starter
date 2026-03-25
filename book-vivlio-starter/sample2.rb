# ブラウン運動のシミュレーション
# 液体中の花粉粒子がランダムに動く様子を再現する
# アインシュタイン, 1905年

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

# ────────────────────────────────────────────────
# 重力レンズ——光の曲がり角を求める
# 一般相対性理論による予測: δ = 4GM / (c²R)
# 1919年の日食観測でエディントンが実証した
# ────────────────────────────────────────────────

G              = 6.674e-11   # 万有引力定数 [m³/kg/s²]
SPEED_OF_LIGHT = 2.9979e8    # 光速 [m/s]
SOLAR_MASS     = 1.989e30    # 太陽の質量 [kg]
SOLAR_RADIUS   = 6.957e8     # 太陽の半径 [m]

def gravitational_deflection(mass_kg, radius_m)
  4 * G * mass_kg / (SPEED_OF_LIGHT**2 * radius_m)
end

def to_arcseconds(radians)
  radians * (180.0 / Math::PI) * 3600
end

# 太陽の縁をかすめる光の曲がり角
deflection_rad = gravitational_deflection(SOLAR_MASS, SOLAR_RADIUS)
deflection_arcsec = to_arcseconds(deflection_rad)

puts "\n重力レンズ——太陽による光の曲がり角"
puts "  理論値: #{deflection_arcsec.round(4)} 秒角"
puts "  エディントンの観測値（1919年）: 約 1.75 秒角"
puts "  → 一般相対性理論の予測と一致！"
