// 厳格モードを呼び出すことで 潜在的なバグを減らす
'use strict';

// イベントリスナの設定
// 開始ボタンを押されるとゲーム開始
const playButton = document.getElementById("play");
playButton.addEventListener('click', jankenHandler);

// player の手を取得
const inputBox = document.getElementById("player_hand_type");
let player = parseInt(inputBox.value);

// conputer の手を 乱数で設定
let computer = rand(0, 2);

// じゃんけんの勝ち負けの結果を表示する関数
function jankenHandler(event) {
  if (player === 0) {
    // === は「厳密等価演算子」で、「等しい」ことを調べます。
    // プレイヤーがグーの時なら
    if (computer === 0) {
      // コンピュータがグーを出した場合、
      alert("あいこです!");
    } else if (computer === 1) {
      // コンピュータがチョキを出した場合
      alert("あなたの勝ちです!");
    } else {
      // コンピュータがパーを出した場合
      alert("あなたの負けです!");
    }
  } else if (player === 1) {
    // プレイヤーがチョキの時に、
    if (computer === 0) {
      // コンピュータがグーを出した場合
      alert("あなたの負けです!");
    } else if (computer === 1) {
      // コンピュータがチョキを出した場合
      alert("あいこです!");
    } else {
      // コンピュータがパーを出した場合
      alert("あなたの勝ちです!");
    }
  } else {
    // プレイヤーがパーの時に、
    if (computer === 0) {
      // コンピュータがグーを出した場合
      alert("あなたの勝ちです!");
    } else if (computer === 1) {
      // コンピュータがチョキを出した場合
      alert("あなたの負けです!");
    } else {
      // コンピュータがパーを出した場合
      alert("あいこです!");
    }
  }
}

// 乱数関数 rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
function rand(min, max){
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
