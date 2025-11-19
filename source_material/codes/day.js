// 元旦から m 月 d 日 までの日数を返す関数
function totalDays(m, d){
       if (m ===  1) { return d; }
  else if (m ===  2) { return 31 + d; }
  else if (m ===  3) { return 31 + 28 + d; }
  else if (m ===  4) { return 31 + 28 + 31 + d; }
  else if (m ===  5) { return 31 + 28 + 31 + 30 + d; }
  else if (m ===  6) { return 31 + 28 + 31 + 30 + 31 + d; }
  else if (m ===  7) { return 31 + 28 + 31 + 30 + 31 + 30 + d; }
  else if (m ===  8) { return 31 + 28 + 31 + 30 + 31 + 30 + 31 + d; }
  else if (m ===  9) { return 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + d; }
  else if (m === 10) { return 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + d; }
  else if (m === 11) { return 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + d; }
  else               { return 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30 + d; }
}

// 九月二十三日を与える
let m =  9;
let d = 23;

// 結果表示
console.log(totalDays(m, d));
