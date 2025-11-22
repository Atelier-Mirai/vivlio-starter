// 閏年を判定する関数
function leapYear(kouki) {
  // 紀元年数ヨリ六百六十ヲ減ジ
  gregorian = kouki - 660;

  // 四ヲ以テ整除シ得ヘキ年ヲ閏年トス
  if ((gregorian % 400 === 0) ||
      (gregorian % 4 === 0 && gregorian % 100 !== 0)) {
    return 1; // 閏年
  } else {
    return 0; // 平年
  }
}

// 結果表示
let kouki = 2682; // 令和四年
console.log(leapYear(kouki));
