# 質量とエネルギーの等価性: E = mc²
# アインシュタイン, 1905年

SPEED_OF_LIGHT = 2.9979e8  # 光速 [m/s]

# 質量からエネルギーを計算する（E = mc²）
# @param mass_kg [Float] 質量 [kg]
# @return [Float] エネルギー [J]
def energy_from_mass(mass_kg)
  mass_kg * SPEED_OF_LIGHT**2
end

# 1gのウランが解放するエネルギー
mass = 1e-3  # 1g → kg
energy = energy_from_mass(mass)
puts "質量 #{mass * 1000}g のエネルギー: #{energy.round(3)} J"
puts "これはTNT火薬 約 #{(energy / 4.184e9).round(1)} トン分に相当します"
