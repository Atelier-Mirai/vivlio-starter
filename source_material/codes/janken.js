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

// 乱数関数
// rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
const rand = (min, max) => {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

// computer の手を 乱数で設定する関数
const shuffleHand = () => {
  if(!isPause){ // 停止中でなければ

    // 現在の手(current_hand)を保持
    let current_hand = computer
    // 次の手(next_hand)の候補を乱数で決定
    next_hand = rand(0, 2) // グー:0, チョキ:1, パー:2
    // 次の手の候補と現在の手が同じなら、
    // 違う手になるまで繰り返す
    while (next_hand === current_hand) {
      next_hand = rand(0, 2)
    }
    // 乱数で選ばれた次の手を、コンピュータの手として設定する
    computer = next_hand
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

// 勝敗更新処理
const updateScore = (result) => {
  // HTML の勝ち表示要素、敗け表示要素を取得します。
  const win  = document.querySelector("#win")
  const lose = document.querySelector("#lose")

  // 勝ちの場合
  if (result === WIN) {
    // 勝数を一つ増やす
    win.textContent = Number(win.textContent) + 1
  } else if (result === LOSE) {
    lose.textContent = Number(lose.textContent) + 1
  }
}

// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  // 「開始」ボタンが押された際に、ボタンの表示を「もう一度」に更新する
  const playButton = document.querySelector("#play")
  playButton.textContent = "もう一度"

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
    alert('引き分けです!')
  } else if (result === LOSE) {
    alert('あなたの負けです!')
    // 敗数を一つ増やす
    updateScore(LOSE)
  } else {
    alert('あなたの勝ちです!')
    // 勝数を一つ増やす
    updateScore(WIN)
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
