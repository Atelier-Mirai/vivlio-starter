// 面積を求める関数を定義
let area = (width, height) => {
  return width * height;
}

// 四角形の幅と高さ
let width1  = 10
let height1 = 20;

// 幅と高さを表示させてみる
console.log(width1);  // => 10 と幅が表示される
console.log(height1); // => 20 と高さが表示される

// 面積を求めたいので、area 関数に幅と高さを渡す
console.log(area(width1, height1); // => 200 と面積が表示される

// 高さを半分にして、正方形にしてみる
height /= 2;
console.log(height1); // => 10 と高さが半分になっている

// もう一度面積を表示させてみる
console.log(area(width1, height1); // => 100 と面積が表示される
