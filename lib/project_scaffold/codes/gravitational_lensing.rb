# 重力レンズ——光の曲がり角を求める
# 一般相対性理論による予測: δ = 4GM / (c²R)
# 1919年の日食観測でエディントンが実証した

# 万有引力定数 G 6.67430(15)
# (15) は末尾2桁の不確かさを示す：6.67430 ± 0.00015
G              = 6.67430e-11  # 万有引力定数 [m³/kg/s²]
SPEED_OF_LIGHT = 2.99792458e8 # 光速 [m/s]
SOLAR_MASS     = 1.9884e30     # 太陽の質量 [kg]
SOLAR_RADIUS   = 6.957e8      # 太陽の半径 [m]

# 重力による光の曲がり角をラジアンで返す（一般相対性理論）
# @param mass_kg [Float] 天体の質量 [kg]
# @param radius_m [Float] 光が最接近する距離（天体の半径など）[m]
# @return [Float] 曲がり角 [ラジアン]
def gravitational_deflection(mass_kg, radius_m)
  4 * G * mass_kg / (SPEED_OF_LIGHT**2 * radius_m)
end

# ラジアンを秒角（arcseconds）に変換する
# 天文学では微小な角度を秒角で表すことが多い（1度 = 3600秒角）
# @param radians [Float] 角度 [ラジアン]
# @return [Float] 角度 [秒角]
def to_arcseconds(radians)
  radians * (180.0 / Math::PI) * 3600
end

# 太陽の縁をかすめる光の曲がり角
deflection_rad = gravitational_deflection(SOLAR_MASS, SOLAR_RADIUS)
deflection_arcsec = to_arcseconds(deflection_rad)

puts "重力レンズ——太陽による光の曲がり角"
puts "  理論値: #{deflection_arcsec.round(4)} 秒角"
puts "  エディントンの観測値（1919年）: 約 1.75 秒角"
puts "  → 一般相対性理論の予測と一致！"
