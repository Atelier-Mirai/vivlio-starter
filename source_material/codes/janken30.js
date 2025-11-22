// 厳格モードを呼び出すことで 潜在的なバグを減らす
'use strict';

// イベントリスナの設定
// 開始ボタンを押されるとゲーム開始
const playButton = document.getElementById("play");
playButton.addEventListener('click', jankenHandler);

// player の手を取得
const inputBox = document.getElementById("player_hand_type");
let player = parseInt(inputBox.value);

// conputer の手を設定
let computer = 0; // グー

// じゃんけんの勝ち負けの結果を表示する関数
function jankenHandler(event) {
  // === は「厳密等価演算子」で、「等しい」ことを調べます。
  if (player === 0) {
    // プレイヤーがグーの時に行う処理を記します。
    // ここでは、alert文を使い、画面表示します。
    alert("あいこです!");
  } else if (player === 1) {
    // プレイヤーがチョキの時の処理を記します。
    alert("あなたの負けです!");
  } else {
    // プレイヤーがパーの時の処理を記します。
    alert("あなたの勝ちです!");
  }
}
