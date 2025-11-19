// CSSセレクタを使ってDOMツリー中のh1要素を取得する
const heading       = document.querySelector("h1");

// 取得したh1要素に含まれるテキストコンテンツ(=JavaScript練習)を取得する
const headingText   = heading.textContent;

// 「おはよう」が取得されているはずなので、表示する。
alert(headingText);
