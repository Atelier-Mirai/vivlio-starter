---
lang: ja
link:
  - rel: 'stylesheet'
    href: 'prism.css'
---

# Prismでの行番号表示

```Ruby``` / ```HTML&CSS``` / ```JavaScript``` / ```C言語``` / ```Java``` での素数を求めるコード例です。

## Ruby

```ruby:prime.rb
def prime?(num)
  return false if num <= 1
  (2..Math.sqrt(num)).none? { |i| num % i == 0 }
end

primes = (1..100).select { |num| prime?(num) }
puts primes
```

```html:prime.html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width">
  <title>1から100までの素数</title>
</head>
<body>
  <h1>1から100までの素数</h1>
  <ul>
    <li>2</li>
    <li>3</li>
    <li>5</li>
    <li>7</li>
    <li>11</li>
    <li>13</li>
    <li>17</li>
    <li>19</li>
    <li>23</li>
    <li>29</li>
    <li>31</li>
    <li>37</li>
    <li>41</li>
    <li>43</li>
    <li>47</li>
    <li>53</li>
    <li>59</li>
    <li>61</li>
    <li>67</li>
    <li>71</li>
    <li>73</li>
    <li>79</li>
    <li>83</li>
    <li>89</li>
    <li>97</li>
  </ul>
</body>
</html>
```

```css:prime.css
body {
  font-family: Arial, sans-serif;
  background-color: #f4f4f4;
  color: #333;
  padding: 20px;

  h1 {
    color: #2c3e50;
  }

  ul {
    list-style-type: none;
    padding: 0;
    li {
      background: #e7f3fe;
      margin: 5px 0;
      padding: 10px;
      border-radius: 5px;
    }
  }
}
```

## JavaScript

```javascript:prime.js
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
```

## C言語

```c:prime.c
#include <stdio.h>
#include <math.h>
#include <stdbool.h>

bool isPrime(int num) {
    if (num <= 1) return false;
    for (int i = 2; i <= sqrt(num); i++) {
        if (num % i == 0) return false;
    }
    return true;
}

int main() {
    printf("1から100までの素数:\n");
    for (int num = 1; num <= 100; num++) {
        if (isPrime(num)) {
            printf("%d ", num);
        }
    }
    printf("\n");
    return 0;
}
```

## Java

```java:Prime.java
public class Prime {

    // 素数判定メソッド
    public static boolean isPrime(int num) {
        if (num <= 1) return false;
        for (int i = 2; i <= Math.sqrt(num); i++) {
            if (num % i == 0) return false;
        }
        return true;
    }

    public static void main(String[] args) {
        System.out.println("1から100までの素数:");
        for (int num = 1; num <= 100; num++) {
            if (isPrime(num)) {
                System.out.print(num + " ");
            }
        }
        System.out.println();
    }
}
```
