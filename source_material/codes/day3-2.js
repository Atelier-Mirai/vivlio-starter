// 元旦から m 月 d 日 までの日数を返す関数
function totalDays(m, d){
  // その月までの日数の累計を納めた配列
  const t = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  // 結果を返す
  return t[m-1] + d;
}

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

// 令和四年九月二十三日を与える
let k = 2682;
let m =    9;
let d =   23;

// 結果表示
if (m <= 2) {
  console.log(totalDays(m, d));
} else {
  console.log(totalDays(m, d) + leapYear(k));
}
