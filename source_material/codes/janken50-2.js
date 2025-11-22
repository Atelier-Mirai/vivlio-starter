// 厳格モードを呼び出すことで 潜在的なバグを減らす
'use strict';

// 定数宣言
// プログラム内で共通して使える定数を宣言する。
// 慣習的に定数名は全て大文字で書かれる。
const DRAW  = 0; // あいこ
const LOSE  = 1; // 負け
const WIN   = 2; // 勝ち

const GUU   = 0; // グー
const CHOKI = 1; // チョキ
const PAA   = 2; // パー

// イベントリスナの設定
// 開始ボタンを押されるとゲーム開始
const playButton = document.getElementById("play");
playButton.addEventListener('click', jankenHandler);

// メイン処理
// player の手を取得
const jankenInputBox = document.getElementById("janken_number");
let player = parseInt(jankenInputBox.value);

// conputer の手を 乱数で設定
let computer = rand(0, 2);

// じゃんけんの勝ち負けの結果を表示する関数
function jankenHandler(event) {
  if (player === GUU) {
    if (computer === GUU) {
      alert("相子です!");
    } else if (computer === CHOKI) {
      alert("あなたの勝ちです!");
    } else {
      alert("あなたの負けです!");
    }
  } else if (player === CHOKI) {
    if (computer === GUU) {
      alert("あなたの負けです!");
    } else if (computer === CHOKI) {
      alert("相子です!");
    } else {
      alert("あなたの勝ちです!");
    }
  } else {
    if (computer === PAA) {
      alert("あなたの勝ちです!");
    } else if (computer === CHOKI) {
      alert("あなたの負けです!");
    } else {
      alert("相子です!"); }
    }
  }
}

// 乱数関数 rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
function rand(min, max){
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
