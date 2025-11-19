/*=============================================================================
 * 🌸の花びらが舞い散るJavaScript
 * https://actyway.com/8351 を元に作成
 *
 * クラスを使わず、配列達で頑張って処理
=============================================================================*/

(
() => {
  // =========================================================================
  // 定数宣言等
  // =========================================================================
  const NUMBER_OF_HANABIRAS = 50; // 花びらの枚数
  const FPS                 = 24; // 一秒間に24回 動かす
  const HANABIRA_HEIGHT     = 30; // 花びらの高さ 回転するので最大値は 29px
  const HANABIRA_WIDTH      = 30; // 花びらの幅 回転するので最大値は 29px
  const HANABIRA_Z_BASE     = 10000; // 花びらの z-index の基準値

  // ウィンドウの高さ
  const windowHeight = window.innerHeight;
  // ウィンドウの幅(スクロールバー除く)
  const windowWidth  = document.documentElement.clientWidth
  // スクロール位置
  let scroll         = document.documentElement.scrollTop || document.body.scrollTop;

  // スクロール時のイベント登録 (スクロール時に花びらがウィンドウ内に納まる為に)
  document.addEventListener('scroll', () => {
    scroll = document.documentElement.scrollTop || document.body.scrollTop;
  }, false);

  // =========================================================================
  // 乱数関数
  // min 以上 max 以下の乱数を返す (integer)
  // min 以上 max 未満の乱数を返す (float)
  // =========================================================================
  let rand = (min, max, type = "integer") => {
    if(type === "integer"){
      return Math.floor(Math.random() * (max-min+1)) + min;
    } else {
      return Math.random() * (max-min) + min;
    }
  };

  // =========================================================================
  // 初期化処理
  // 🌸の花びらのための新しい div 要素を作成し、body の末尾に追加
  // 作業用の 花びら配列達も適宜初期化する
  // =========================================================================

  const divSakura = document.createElement("div");
  document.body.after(divSakura);

  // 変数宣言
  // -------------------------------------------------------------------------
  let domHanabiras = []; // 花びら要素の配列
  let jsHanabiras  = []; // 花びらjsオブジェクトの配列
  let jsHanabirasY = []; // 花びら達の X 座標の配列
  let jsHanabirasX = []; // 花びら達の Y 座標の配列
  let tremorMax    = []; // 花びらの連続して揺らげる回数の配列
  let tremorCount  = []; // 花びらの揺いだ累積回数の配列
  let fallingSpeed = []; // 落下速度の配列


  // それぞれの花びらについて、位置等の初期設定を行う
  // -------------------------------------------------------------------------
  for(let i = 0; i < NUMBER_OF_HANABIRAS; i++){
    // 花びらの div を作る
    let domHanabira = document.createElement('div');

    // ランダムに生成した初期表示位置を設定する
    jsHanabirasX[i] = rand(HANABIRA_WIDTH / 2, windowWidth - HANABIRA_WIDTH);
    jsHanabirasY[i] = rand(-500, 0) + scroll;
    domHanabira.setAttribute('style', `z-index: ${HANABIRA_Z_BASE + i}; top: ${jsHanabirasY[i]}px; left: ${jsHanabirasX[i]}px;`);

    // ランダムに生成した花びらの色とアニメーションのための css class を設定する
    domHanabira.setAttribute('class', `hana t${rand(1, 5)} a${rand(1, 5)}`);

    // 扱いやすくするために、花びら要素達を配列に格納
    domHanabiras[i] = domHanabira;

    // 作成した花びらをDOMに追加、画面に表示されるようにする
    divSakura.appendChild(domHanabira);

    // 連続して同一方向へ揺らげる回数をランダムに生成
    tremorMax[i]    = rand(15, 50);
    // 連続して同一方向へ揺らいだ回数を0で初期化
    tremorCount[i]  = 0;
    // 落下速度をランダムに生成
    fallingSpeed[i] = rand(1, 3);
  }

  // =========================================================================
  // メイン処理
  // 生成したそれぞれの花びらの位置情報を更新し、画面に反映する。
  // =========================================================================
  setInterval(() => {
    // 各花びらに対し移動処理を繰り返す
    for(let i = 0; i < NUMBER_OF_HANABIRAS; i++){
      // 花びらの位置（top）がウィンドウ内なら
      if (jsHanabirasY[i] < scroll + windowHeight - HANABIRA_HEIGHT){
        // 揺らいだ回数が、連続して揺らげる回数以内なら、右へ移動させる
        if (tremorCount[i] <= tremorMax[i]){
          jsHanabirasX[i] += rand(0.3, 0.6, "float");
          // もし、花びらが右にはみ出すようなら、左端に移動させる
          if (jsHanabirasX[i] + HANABIRA_WIDTH >= windowWidth){
            jsHanabirasX[i] = HANABIRA_WIDTH;
          }
          // 連続して右へ揺らいだならば、今度は左へ移動させる
        } else {
          jsHanabirasX[i] -= rand(0.3, 0.6, "float");
          // もし、花びらが左にはみ出すようなら、右端に移動させる
          if (jsHanabirasX[i] <= HANABIRA_WIDTH / 2){
            jsHanabirasX[i] = windowWidth - HANABIRA_WIDTH;
          }
        }

        // 右へtremorMax回、左へtremorMax回、揺らいだら、累積回数を0に初期化
        // これにより、再び、右へ揺らげるようにする
        if (tremorCount[i] >= tremorMax[i] * 2){
          tremorCount[i] = 0;
        }

      // 花びらがウィンドウの下まできたら
      } else {
        // 花びらをウィンドウの上に戻し、画面幅内に表示する
        jsHanabirasX[i] = rand(0, windowWidth - HANABIRA_WIDTH);
        jsHanabirasY[i] = scroll;
      }

      // 表示位置に落下速度分を追加する
      jsHanabirasY[i]               += fallingSpeed[i];

      // 花びらの位置を設定する
      domHanabiras[i].style.left = `${jsHanabirasX[i]}px`;
      domHanabiras[i].style.top  = `${jsHanabirasY[i]}px`;
      // 同一方向への移動回数更新
      tremorCount[i]++;
    }
  }, 1000 / FPS);
}
)();
