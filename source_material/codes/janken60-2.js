// 厳格モードを呼び出すことで 潜在的なバグを減らす
'use strict';

// 定数宣言
// プログラム内で共通して使う定数を宣言する。
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

// player の手を取得
const inputBox = document.getElementById("player_hand_type");
let player = parseInt(inputBox.value);

// conputer の手を 乱数で設定
let computer = rand(0, 2);

// じゃんけんの勝ち負けの結果を表示する関数
function jankenHandler(event) {
  // judge関数に、プレイヤーとコンピュータの手を渡して、
  // 勝敗(相子なら0 , 負けなら1, 勝ちなら2)を得ます。
  const result = judge(player, computer);

  if (result === DRAW) {
    alert('引き分けです!');
  } else if (result === LOSE) {
    alert('あなたの負けです!');
  } else {
    alert('あなたの勝ちです!');
  }
}

// 乱数関数 rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
function rand(min, max){
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// プレイヤーの手とコンピュータの手が与えられると、
// 0: 引き分け 1: 負け 2: 勝ち を返す関数
function judge(player, computer) {
  return (player - computer + 3) % 3;
}
