// 元旦から m 月 d 日 までの日数を返す関数
function totalDays(m, d){
  // その月までの日数の累計を納めた配列
  const t = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  // 結果を返す
  return t[m-1] + d;
}

// 九月二十三日を与える
let m =  9;
let d = 23;

// 結果表示
console.log(totalDays(m, d));
