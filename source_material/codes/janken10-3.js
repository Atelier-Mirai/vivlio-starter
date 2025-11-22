// 厳格モードを呼び出すことで 潜在的なバグを減らす
'use strict';

// HTML文書から、IDがplayである要素(=開始ボタン)を取得し、
// play_button という変数に格納(代入)する。
const playButton = document.getElementById("play");

// イベントリスナの追加
// playButtonがクリックされたときに、
// jankenHandler という関数が呼ばれるようにする。
playButton.addEventListener("click", jankenHandler);

// jankenHandler 関数
// じゃんけんの勝ち負けの結果を表示する
function jankenHandler(event) {
  alert("あなたの勝ちです!");
}
