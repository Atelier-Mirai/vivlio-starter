# 2〜100 のうち素数だけを抽出して表示するメソッド版サンプル
def prime?(n)
  # 2 は素数
  return true if n == 2

  # 2 以外の偶数は素数ではない
  return false if n.even?

  # 3 から √n までの奇数だけで割り切れるかを調べる
  limit = Math.sqrt(n).to_i
  (3..limit).step(2).none? { |i| n % i == 0 }
end

primes = (2..100).select { |n| prime?(n) }
puts primes

