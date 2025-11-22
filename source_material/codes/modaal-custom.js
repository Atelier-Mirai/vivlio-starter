// inline (基本)
$(".inline").modaal();

// フルスクリーン
$(".fullscreen").modaal({
  fullscreen: true
});

// 画像(一枚)
$('.image').modaal({
  type: 'image'
});

// 画像ギャラリー(複数枚)
$('.gallery').modaal({
  type: 'image'
});

// 動画(YouTube)
$('.youtube').modaal({
  type: 'video'
});

// 動画(Vimeo)
$('.vimeo').modaal({
  type: 'video'
});

// iframe
let w = $(window).width();  // 画面幅を取得
let h = $(window).height(); // 画面高を取得
let bc = '';
if (w >= 768) {   // iPad 以上の画面幅の場合
  w = w * 0.8;    // w *= 0.8; と省略して書くことも出来ます
  h = h * 0.8;
  bc = '#ff0000'; // 背景色を赤色にする
} else {          // iPhone で閲覧の場合
  bc = '#0000ff'; // 背景色を青色にする
}

$('.iframe').modaal({
  type: 'iframe',
  width: w,
  height: h,
  background: bc
});

// 確認画面
$('.confirm').modaal({
  type: 'confirm',
  confirm_button_text: '確認',
  confirm_cancel_button_text: '取消',
  confirm_title: '確認画面です',
  confirm_content: '<p>登録してもよろしいですか</p>',
  confirm_callback: () => {
    alert('登録しました');
  },
  confirm_cancel_callback: () => {
    alert('取り消しました');
  }
});
