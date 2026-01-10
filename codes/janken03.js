// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  // 繰り返し処理
  let i = 0
  while (i < 3) {
    alert("あなたの勝ちです")
    i = i + 1
  }

  // for(let i = 0; i < 3; i++) {
  //   alert("あなたの勝ちです")
  // }
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
