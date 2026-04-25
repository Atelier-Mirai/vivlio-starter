# 素数列挙: エラトステネスの篩
# 大量の素数を高速に列挙するアルゴリズム

# エラトステネスの篩で n 以下の素数を列挙する
# @param n [Integer] 上限値
# @return [Array<Integer>] 素数の配列
def sieve_of_eratosthenes(n)
  return [] if n < 2

  is_prime = Array.new(n + 1, true)
  is_prime[0] = is_prime[1] = false

  (2..Math.sqrt(n).to_i).each do |i|
    next unless is_prime[i]

    (i * i..n).step(i) { is_prime[it] = false }
  end

  is_prime.each_index.select { is_prime[it] }
end

# 1000以下の素数を列挙
primes = sieve_of_eratosthenes(1000)
puts "1000以下の素数: #{primes.size}個"
puts "最大の素数: #{primes.last}"

# 双子素数（差が2の素数ペア）を抽出
twins = primes.each_cons(2).select { |a, b| b - a == 2 }
puts "双子素数: #{twins.size}組"
twins.last(5).each { |a, b| puts "  (#{a}, #{b})" }
