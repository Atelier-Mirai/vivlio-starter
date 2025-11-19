// 長方形クラス(型)の宣言
class Rectangle {
  // 構築子
  constructor(height, width) {
    this.width  = width;  // 幅
    this.height = height; // 高さ
  }

  // 面積を求めるメソッド(関数)
  area() {
    return this.width * this.height;
  }
}

// 実際に使ってみる
// 幅10cm, 高さ20cm の長方形のインスタンス(実例)を作成
rect1 = new Rectangle(10, 20);

// 幅と高さを表示させてみる
console.log(rect1.width);  // => 10 と幅が表示される
console.log(rect1.height); // => 20 と高さが表示される

// 面積を求めたいので、area メソッドを呼び出す
console.log(rect1.area()); // => 200 と面積が表示される

// 高さを半分にして、正方形にしてみる
rect1.height /= 2;
console.log(rect1.height); // => 10 と高さが半分になっている

// もう一度面積を表示させてみる
console.log(rect1.area()); // => 100 と面積が表示される
