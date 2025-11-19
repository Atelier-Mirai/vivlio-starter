= 文字の演出効果

== シャッフルテキスト

@<href>{https://ics.media/entry/15498/,手軽にテキストシャッフル演出ができるJavaScriptライブラリ「shuffle-text」を公開} という記事がございます。

//quote{
JavaScriptライブラリ「shuffle-text」を公開しました。shuffle-textはテキストシャッフル（文字列がランダムで切り替わる演出）の表現を行うためのライブラリで、SPA（シングル・ページ・アプリケーション）やゲームの演出やスペシャルコンテンツなどの演出に役立ちます。
//}


元記事は、@<code>{NPM} を利用して使う方法が説明されておりましたが、
@<href>{https://github.com/ics-ikeda/shuffle-text} で公開されている examples から、HTML と JavaScript を使った基本的な使い方をご紹介いたします。

マウスカーソルをのせると、文字がシャッフルされる演出がなされます。
@<href>{https://wave-improve.netlify.app/shuffle_text/index.html,動作例}と@<href>{https://github.com/Atelier-Mirai/wave-improve/tree/master/shuffle_text,ソースコード} です。ご参考になれば幸いです。

//image[shuffle_text][作成例][width=80%]

まずは、次のように @<file>{index.html} を作成いたします。

//list[][index.html][1]{
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>shuffle-text</title>
  <meta name="viewport" content="width=device-width">

  <!-- 簡単に見栄えの良いページを作るためのスタイルシート -->
  <link rel="stylesheet" href="https://unpkg.com/sakura.css/css/sakura.css">
</head>

<body>
  <h1><a href="https://ics.media/entry/15498/">shuffle-text</a></h1>
  <img src="shuffle-text.webp" alt="">
  <p>
    shuffle-textはテキストシャッフル（文字列がランダムで切り替わる演出）の
    表現を行うためのライブラリです。
    ウェブサイトでマウスが触れたときに演出ができます。
  </p>

  <h3>使い方</h3>
  <p>シャッフルしたい要素に class="shuffle" とクラス名を付与します。</p>

  <ul>
    <li class="shuffle">01/01 「トップページ」更新しました。</li>
    <li class="shuffle">01/02 「会社案内」更新しました。</li>
    <li class="shuffle">01/03 「お問い合わせ」更新しました。</li>
    <li class="shuffle">01/04 「最新情報」更新しました。</li>
  </ul>

  <!-- 再読み込みボタン -->
  <button id="reload">再読み込み</button>
  <script>
    document.getElementById("reload").addEventListener("click", () => {
      location.reload();
    });
  </script>

  <footer>
    <p>shuffle-text.js is under MIT Licence.</p>
    <p>&copy; copyright 2012-2021,<a href="http://clockmaker.jp/">clockmaker.jp</a></p>
  </footer>

  <!-- JavaScript を読み込む -->
  <script src="shuffle-text.js"></script>
  <script src="shuffle-text-custom.js"></script>
</body>
</html>
//}

@<code>{<li class="shuffle">01/01 「トップページ」更新</li>}と、@<b>{シャッフルしたい要素に @<code>{class="shuffle"} とクラス名を付与}する点がポイントです。

@<code>{</body>} 直前に、シャッフルテキスト本体である @<file>{shuffle-text.js} と、簡単に効果を適用できるための @<file>{shuffle-text-custom.js} を呼び出すようコーディングしたら完成です。

//blankline
iPhone / iPad で何度も効果を楽しめるよう、際読み込みボタンも用意しています。

//list[][index.html][31]{
<!-- 再読み込みボタン -->
<button id="reload">再読み込み</button>
<script>
  document.getElementById("reload").addEventListener("click", () => {
    location.reload();
  });
</script>
//}

//blankline
@<code>{.shuffle}クラスに、簡単に効果を適用するための @<file>{shuffle-text-custom.js} です。
ご興味ある方のために、コメントもつけておりますので、お読みください。
//list[][shuffle-text-custom.js][1]{
// ページ読み込み時に実行されるよう、イベントリスナを指定。
window.addEventListener('load', init);

// 初期化処理を行う関数
function init() {
  // ShuffleTextのインスタンス達を格納する配列
  let effectList = [];
  // shuffle クラスが付与された全ての要素を取得する。
  // (<li class="shuffle">と書かれた要素全て)
  let elementList = document.querySelectorAll('.shuffle');

  // elementListの全てのメンバーに対して、繰り返し処理を行う。
  for (let i = 0; i < elementList.length; i++) {

    // i番目のメンバーを取得して、elementという変数に代入。
    let element = elementList[i];
    // カスタムdata属性を付与する。
    // <li class="shuffle">01/01「トップページ」更新</li>
    // という元の要素を、
    // <li class="shuffle" data-index="1">01/01「トップページ」更新</li>
    // に変更する。カスタムdata属性 data-index="1" が付与されている。
    element.dataset.index = i;
    // ShuffleTextクラスのインスタンスを作成し、effectListに格納する。
    effectList[i] = new ShuffleText(element);

    // マウスを載せたときに再生するよう、イベントリスナを指定する。
    element.addEventListener('mouseenter', function () {
      // <li>要素は、次のようになっている。
      // <li class="shuffle" data-index="1">01/01「トップページ」更新</li>
      // this.dataset.index と書くと data-index="1" の 1 を取得できる。
      effectList[this.dataset.index].start();
      // effectList[1].start(); と等価だが、
      // シャッフル効果を付けたい要素が複数ある場合に、
      // this.dataset.index で それぞれの要素を指定できる。
    });

    // マウスを離した時に再生するよう、イベントリスナを指定する。
    element.addEventListener('mouseleave', function () {
      effectList[this.dataset.index].start();
    });

    // ページを読み込んだときに、初回を再生する。
    effectList[i].start();
  }
}
//}


//blankline
シャッフルテキスト本体です。

シャッフル効果が日本語になるよう ポラーノの広場(宮沢賢治)に変更した他は、ほぼ原作者 池田 泰延さんのコードのままです。
//list[][shuffle-text.js][1]{
(function (global, factory) {
  typeof exports === 'object' && typeof module !== 'undefined' ? module.exports = factory() : typeof define === 'function' && define.amd ? define(factory) : (global = typeof globalThis !== 'undefined' ? globalThis : global || self, global.ShuffleText = factory());
}(this, (function () {
  'use strict';
  /**
   * ShuffleTextはDOMエレメント用ランダムテキストクラスです。
   * @author Yasunobu Ikeda
   * @since 2012-02-07
   */
  let ShuffleText = (function () {
    // DOMエレメントです。
    function ShuffleText(element) {
      let _a;
      // シャッフル効果が日本語になるよう ポラーノの広場(宮沢賢治)に変更
      this.sourceRandomCharacter = "あのイーハトーヴォのすきとおった風、夏でも底に冷たさをもつ青いそら、うつくしい森で飾られたモリーオ市、郊外のぎらぎらひかる草の波";
      // this.sourceRandomCharacter = "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
      this.emptyCharacter           = "-"; // 空白に用いる文字列です
      this.duration                 = 600; // エフェクトの実行時間（ミリ秒）
      this._isRunning               = false;
      this._originalStr             = "";
      this._originalLength          = 0;
      this._timeCurrent             = 0;
      this._timeStart               = 0;
      this._randomIndex             = [];
      this._element                 = null;
      this._requestAnimationFrameId = 0;
      this._element                 = element;
      this.setText((_a = element.textContent) !== null && _a !== void 0 ? _a : "");
    }

    // シャッフル対象となるテキストを設定します。
    ShuffleText.prototype.setText = function (text) {
      this._originalStr    = text;
      this._originalLength = text.length;
    };
    Object.defineProperty(ShuffleText.prototype, "isRunning", {
      get: function () {
        return this._isRunning; // 再生中かどうかを示すブール値です。
      },
      enumerable: false,
      configurable: true
    });

    // Play effect. 再生を開始します。
    ShuffleText.prototype.start = function () {
      let _this = this;
      this.stop();
      this._randomIndex = [];
      let str = "";
      for (let i = 0; i < this._originalLength; i++) {
        let rate = i / this._originalLength;
        this._randomIndex[i] = Math.random() * (1 - rate) + rate;
        str += this.emptyCharacter;
      }
      this._timeStart = new Date().getTime();
      this._isRunning = true;
      this._requestAnimationFrameId = requestAnimationFrame(function () {
        _this._onInterval();
      });
      if (this._element) {
        this._element.textContent = str;
      }
    };

    // Stop effect. 停止します。
    ShuffleText.prototype.stop = function () {
      this._isRunning = false;
      cancelAnimationFrame(this._requestAnimationFrameId);
    };

    // メモリ解放のためインスタンスを破棄します。
    ShuffleText.prototype.dispose = function () {
      cancelAnimationFrame(this._requestAnimationFrameId);
      this._isRunning               = false;
      this.duration                 = 0;
      this._originalStr             = "";
      this._originalLength          = 0;
      this._timeCurrent             = 0;
      this._timeStart               = 0;
      this._randomIndex             = [];
      this._element                 = null;
      this._requestAnimationFrameId = 0;
    };

    // インターバルハンドラーです。
    ShuffleText.prototype._onInterval = function () {
      let _this = this;
      this._timeCurrent = new Date().getTime() - this._timeStart;
      let percent = this._timeCurrent / this.duration;
      let str = "";
      for (let i = 0; i < this._originalLength; i++) {
        if (percent >= this._randomIndex[i]) {
          str += this._originalStr.charAt(i);
        } else if (percent < this._randomIndex[i] / 3) {
          str += this.emptyCharacter;
        } else {
          str += this.sourceRandomCharacter.charAt(Math.floor(Math.random() * this.sourceRandomCharacter.length));
        }
      }
      if (percent > 1) {
        str = this._originalStr;
        this._isRunning = false;
      }
      if (this._element) {
        this._element.textContent = str;
      }
      if (this._isRunning) {
        this._requestAnimationFrameId = requestAnimationFrame(function () {
          _this._onInterval();
        });
      }
    };
    return ShuffleText;
  }());
  return ShuffleText;
})));

//}
