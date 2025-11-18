# エラトステネスの篩を使って 2〜100 の素数を求めて表示するサンプル
LIMIT = 100
 
# true を「素数の候補」として初期化（インデックス = その数を表す）
is_prime = Array.new(LIMIT + 1, true)
is_prime[0] = is_prime[1] = false
 
# 2 から √LIMIT までの整数 p について、p の倍数を「素数ではない」と印を付ける
2.upto(Math.sqrt(LIMIT).to_i) do |p|
  next unless is_prime[p]
 
  # p^2 未満の倍数は、より小さい素数の段階ですでに篩い落とされているので p^2 から開始する
  (p * p).step(LIMIT, p) do |multiple|
    is_prime[multiple] = false
  end
end
 
# true が残っていいるインデックスだけを素数として取り出す
primes = (2..LIMIT).select { |n| is_prime[n] }
puts primes
