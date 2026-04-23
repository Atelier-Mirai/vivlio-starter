# ローレンツ因子: γ = 1 / √(1 - v²/c²)
# 高速で移動する物体では時間が遅れる

SPEED_OF_LIGHT = 2.99792458e8  # 光速 [m/s]

# ローレンツ因子 γ を計算する
# 速度が光速に近づくほど γ は大きくなり、時間の遅れが顕著になる
# @param velocity_ratio [Float] 光速を1としたときの速度（例: 0.9 = 光速の90%）
# @return [Float] ローレンツ因子 γ（常に1以上）
def lorentz_factor(velocity_ratio)
  1.0 / Math.sqrt(1 - velocity_ratio**2)
end

# 時間の遅れを計算する（特殊相対性理論）
# 高速で移動する系では、静止系から見て時間の進みが遅くなる
# @param proper_time [Float] 移動する系での経過時間（固有時間）
# @param velocity_ratio [Float] 光速を1としたときの速度
# @return [Float] 静止系（地球）から見た経過時間
def time_dilation(proper_time, velocity_ratio)
  proper_time * lorentz_factor(velocity_ratio)
end

# 光速の90%で飛ぶ宇宙船では、時間がどれだけ遅れるか？
velocities = [0.1, 0.2, 0.5, 0.8, 0.9, 0.99, 0.999]

puts "速度別・時間の遅れ（宇宙船内で1年経過したとき、地球では何年？）"
velocities.each do |v|
  gamma = lorentz_factor(v)
  elapsed = time_dilation(1.0, v)
  puts "  光速の #{(v * 100).round(1)}%: γ = #{gamma.round(4)}, 地球時間 = #{elapsed.round(4)} 年"
end
