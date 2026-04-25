# 素数判定: 試し割り法
# 最もシンプルな素数判定アルゴリズム

# 与えられた整数が素数かどうかを判定する
# @param n [Integer] 判定対象の自然数
# @return [Boolean] 素数なら true
def prime?(n)
  return false if n < 2
  return true if n < 4

  (2..Math.sqrt(n).to_i).none? { n % it == 0 }
end

# 1〜50 の素数を列挙する
primes = (1..50).select { prime?(it) }
puts "50以下の素数: #{primes.join(', ')}"
puts "個数: #{primes.size}"
