// 閏年を判定する関数
function leapYear(kouki) {
  // 四ヲ以テ整除シ得ヘキ年ヲ閏年トス
  if (kouki % 4 === 0) {
    // 紀元年数ヨリ六百六十ヲ減ジテ百ヲ以テ整除シ得ヘキモノノ中更
    if ((kouki-660)%100 === 0) {
      // 更ニ四ヲ以テ其ノ商ヲ整除シ得サル年ハ平年トス
      if ( ((kouki-660)/100) % 4 !== 0) {
        return 0; // 平年
      } else {
        return 1; // 閏年
      }
    }
    return 1; // 閏年
  } else {
    // 四ヲ以テ整除シ得サル年
    return 0; // 平年
  }
}

// 結果表示
let kouki = 2682; // 令和四年
console.log(leapYear(kouki));
