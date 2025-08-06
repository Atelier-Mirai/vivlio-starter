---
lang: ja
link:
  - rel: 'stylesheet'
    href: 'prism.css'
---

# Prismでの行番号表示

```Ruby``` / ```HTML&CSS``` / ```JavaScript``` / ```C言語``` / ```Java``` での素数を求めるコード例です。

## Ruby

Rubyで素数を求めるプログラムの例です。
ソースコードです。
```include:prime.rb```

直接記述した例です。
```ruby:prime.rb
def prime?(num)
  return false if num <= 1
  (2..Math.sqrt(num)).none? { |i| num % i == 0 }
end

primes = (1..100).select { |num| prime?(num) }
puts primes
```

## HTML

HTMLで素数を表示する例です。
```include:prime.html```

直接記述した例です。
```html:prime.html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width">
  <title>1から10までの素数</title>
</head>
<body>
  <h1>1から10までの素数</h1>
  <ul>
    <li>2</li>
    <li>3</li>
    <li>5</li>
    <li>7</li>
  </ul>
</body>
</html>
```

## CSS

CSSで素数を表示する例です。
```include:prime.css```

直接記述した例です。
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

JavaScriptで素数を求めるプログラムの例です。
```include:prime.js```

直接記述した例です。
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

C言語で素数を求めるプログラムの例です。
5行目から11行目までです。
```include:prime.c:5-11```

全体のソースコードです。
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

Javaで素数を求めるプログラムの例です。
```include:Prime.java```

直接記述した例です。
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
