// computer の手を設定(仮)
let computer = 0 // グー

// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  // player の手を設定(仮)
  let player = 0 // グー

  // === は「厳密等価演算子」で、「等しい」ことを調べます。
  if (player === 0) {
    // プレイヤーがグーの時に行う処理を記します。
    // ここでは、alert文を使い、画面表示します。
    alert("あいこです")
  } else if (player === 1) {
    // プレイヤーがチョキの時の処理を記します。
    alert("あなたの負けです")
  } else {
    // プレイヤーがパーの時の処理を記します。
    alert("あなたの勝ちです")
  }
}

// イベントリスナの設定
// グー・チョキ・パー ぞれぞれのボタンが押されたときに、
// jankenHandler関数が呼ばれるように、登録する。
const guuButton   = document.querySelector("#guu")
const chokiButton = document.querySelector("#choki")
const paaButton   = document.querySelector("#paa")
guuButton.addEventListener("click", jankenHandler)
chokiButton.addEventListener("click", jankenHandler)
paaButton.addEventListener("click", jankenHandler)
