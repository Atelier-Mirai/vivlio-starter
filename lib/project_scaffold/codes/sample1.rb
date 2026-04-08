# 質量とエネルギーの等価性: E = mc²
# アインシュタイン, 1905年

SPEED_OF_LIGHT = 2.9979e8  # 光速 [m/s]

def energy_from_mass(mass_kg)
  mass_kg * SPEED_OF_LIGHT**2
end

# 1gのウランが解放するエネルギー
mass = 1e-3  # 1g → kg
energy = energy_from_mass(mass)
puts "質量 #{mass * 1000}g のエネルギー: #{energy.round(3)} J"
puts "これはTNT火薬 約 #{(energy / 4.184e9).round(1)} トン分に相当します"

# ───────────────────────────────────────
# ローレンツ因子: γ = 1 / √(1 - v²/c²)
# 高速で移動する物体では時間が遅れる
# ───────────────────────────────────────

def lorentz_factor(velocity_ratio)
  # velocity_ratio: 光速を1としたときの速度（例: 0.9 = 光速の90%）
  1.0 / Math.sqrt(1 - velocity_ratio**2)
end

def time_dilation(proper_time, velocity_ratio)
  proper_time * lorentz_factor(velocity_ratio)
end

# 光速の90%で飛ぶ宇宙船では、時間がどれだけ遅れるか？
velocities = [0.5, 0.9, 0.99, 0.999]

puts "\n速度別・時間の遅れ（宇宙船内で1年経過したとき、地球では何年？）"
velocities.each do |v|
  gamma = lorentz_factor(v)
  elapsed = time_dilation(1.0, v)
  puts "  光速の #{(v * 100).round(1)}%: γ = #{gamma.round(4)}, 地球時間 = #{elapsed.round(4)} 年"
end
