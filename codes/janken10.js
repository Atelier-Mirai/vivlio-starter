// 定数宣言
// プログラム内で共通して使う定数を宣言する。
// 慣習的に定数名は全て大文字で書かれる。
const DRAW  = 0 // あいこ
const LOSE  = 1 // 負け
const WIN   = 2 // 勝ち

const FPS   = 4 // 一秒間あたり、4コマ表示する

// グローバル変数宣言
let computer       // コンピュータの手(グー:0, チョキ:1, パー:2)
let isPause = true // グー・チョキ・パーの切替アニメを制御する為の変数

// 切替アニメ停止処理
const pause = () => {
  isPause = true
}

// 切替アニメ再開処理
const resume = () => {
  isPause = false
}

// 乱数関数 rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
const rand = (min, max) => {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

// computer の手を 乱数で設定する関数
const shuffleHand = () => {
  if(!isPause){ // 停止中でなければ

    computer = rand(0, 2)
    // 設定できているか、確認する。
    console.log(`computer: ${computer}`)

    // コンピュータの手(0, 1, 2)によって、画像(や代替文字列)を変更する
    document.querySelector("#hand").src = ["images/guu.webp", "images/choki.webp", "images/paa.webp"][computer]
    document.querySelector("#hand").alt = ["グー", "チョキ", "パー"][computer]
  }

  // 一定間隔で、shuffleHand 関数を呼び続ける
  setTimeout(shuffleHand, 1000 / FPS)
}

// プレイヤーの手とコンピュータの手が与えられると、
// 0: 引き分け 1: 負け 2: 勝ち を返す関数
const judge = (player, computer) => {
  return (player - computer + 3) % 3
}

// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  // 切替アニメ停止処理実行
  pause()

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

// playボタンがクリックされた時には、resume関数を実行して、
// じゃんけんの切替アニメが再開(resume)されるようにする
const playButton = document.querySelector("#play")
playButton.addEventListener("click", resume)

// コンピュータの手を変更する処理を呼び出す
shuffleHand()

// 開始ボタンを押すと、アニメーション開始、
// グーチョキパーボタンを押すとアニメーションが止まるようになりました
// かくかくして見えます。必ず違う手を出すようにしましょう
