// 定数宣言
// プログラム内で共通して使う定数を宣言する。
// 慣習的に定数名は全て大文字で書かれる。
const DRAW  = 0 // あいこ
const LOSE  = 1 // 負け
const WIN   = 2 // 勝ち

// 乱数関数 rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
const rand = (min, max) => {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

// computer の手を 乱数で設定
let computer = rand(0, 2)
// 設定できているか、確認する。
console.log(`computer: ${computer}`)

// プレイヤーの手とコンピュータの手が与えられると、
// 0: 引き分け 1: 負け 2: 勝ち を返す関数
const judge = (player, computer) => {
  return (player - computer + 3) % 3
}

// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  // プレイヤーの手の取得
  const player = Number(event.target.value)
  // 取得できているか、確認する。
  console.log(`player:   ${player}`)

  // judge関数に、プレイヤーとコンピュータの手を渡して、
  // 勝敗(相子なら0 , 負けなら1, 勝ちなら2)を得ます。
  const result = judge(player, computer)
  // 判定できているか、確認する。
  console.log(`result:   ${result}`)

  if (result === DRAW) {
    alert("引き分けです")
  } else if (result === LOSE) {
    alert("あなたの負けです")
  } else {
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
