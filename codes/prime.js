function isPrime(num) {
    if (num <= 1) return false;
    for (let i = 2; i <= Math.sqrt(num); i++) {
        if (num % i === 0) return false;
    }
    return true;
}

const primes = [];
for (let num = 1; num <= 100; num++) {
    if (isPrime(num)) {
        primes.push(num);
    }
}

console.log(primes);