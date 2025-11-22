// 厳格モードを呼び出すことで 潜在的なバグを減らす
'use strict';

// 定数宣言
const DRAW  = 0; // 引き分け
const LOSE  = 1; // 負け
const WIN   = 2; // 勝ち

const GUU   = 0; // グー
const CHOKI = 1; // チョキ
const PAA   = 2; // パー

const FPS   = 24; // 一秒間あたり、24コマ表示する

// グローバル変数宣言
let isPause = true;   // グー・チョキ・パーの切替アニメを制御するための変数
let computer; // コンピュータの手（グー:0、チョキ:1、パー:2 のいずれか)

// メイン処理
function main(){
  if(!isPause){ // 停止中でなければ
    computer = rand(0, 2);
    document.getElementById('computer_hand_type').src =
            ["guu.webp", "choki.webp", "paa.webp"][computer];
  }
  setTimeout(main, 1000 / FPS);
}

// ボタン初期化関数
function initButton() {
  const guu_button   = document.getElementById("guu");
  const choki_button = document.getElementById("choki");
  const paa_button   = document.getElementById("paa");
  guu_button.addEventListener('click', jankenHandler);
  choki_button.addEventListener('click', jankenHandler);
  paa_button.addEventListener('click', jankenHandler);

  // playボタンがクリックされた時には、resume関数を実行して、
  // じゃんけんの切替アニメが再開(resume)されるようにする。
  const play_button  = document.getElementById("play");
  play_button.addEventListener('click', resume);
}

// じゃんけんの勝敗を取り扱う関数
function jankenHandler(event) {
  // 開始ボタンが押された際に、ボタン表示を、「もう一度」に更新する
  const play_button  = document.getElementById("play");
  play_button.innerText = "もう一度";

  // アニメーション停止処理実行
  pause();

  // プレイヤーの手の取得
  const player   = parseInt(event.target.value);
  // 勝敗結果の取得
  const result = judge(player, computer);
  // 勝敗に応じ、メッセージ表示＆勝敗更新
  if (result === DRAW) {
    alert('引き分けです!');
  } else if (result === LOSE) {
    alert('あなたの負けです!');
    // 敗数を一つ増やす
    updateScore(LOSE);
  } else {
    alert('あなたの勝ちです!');
    // 勝数を一つ増やす
    updateScore(WIN);
  }
}

// じゃんけんの効果的な勝敗判定アルゴリズム
function judge(player, computer) {
  return (player - computer + 3) % 3;
}

// 勝敗更新処理
function updateScore(result) {
  const win  = document.getElementById("win");
  const lose = document.getElementById("lose");

  if (result === WIN) { // 勝ちの場合
    win.innerText = parseInt(win.textContent) + 1;
  } else if (result === LOSE) {
    lose.innerText = parseInt(lose.textContent) + 1;
  }
}

// 切替アニメ停止処理
function pause(){
  isPause = true;
}

// 切替アニメ再開処理
function resume(){
  isPause = false;
}

// 乱数を返す関数
// rand(0, 2)と呼び出せば、0, 1, 2 と グーチョキパー の乱数を返す
function rand(min, max){
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// 実際の処理の開始
initButton(); // ボタンの初期化を行う。
pause();      // 切替アニメを停止状態にする。
main();       // 切替アニメを実行待ちにし、
              // 開始ボタンが押されると切替アニメが実行される。
