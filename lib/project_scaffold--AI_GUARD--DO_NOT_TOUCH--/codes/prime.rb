# frozen_string_literal: true

def prime?(num)
  return false if num <= 1

  (2..Math.sqrt(num)).none? { |i| (num % i).zero? }
end

primes = (1..100).select { |num| prime?(num) }
puts primes
