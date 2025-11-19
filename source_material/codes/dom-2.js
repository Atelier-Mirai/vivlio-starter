// 厳格モードを呼び出すことで 潜在的なバグを減らす
'use strict';

// HTML文書から、IDがplayである要素(=開始ボタン)を取得し、
// play_button という変数に格納(代入)する。
const play_button  = document.getElementById("play");

// 取得した開始ボタンの文字を「もう一度」に更新する。
play_button.innerText = "もう一度";
