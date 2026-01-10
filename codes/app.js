/*=========================================================================
  サービスワーカーの登録を行う
  // https://jam25.jp/javascript/about-pwa/
  // https://laboradian.com/create-offline-site-using-sw/
=========================================================================*/
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js")
    .then((registration) => {
      // 登録成功
      // console.log(`Service Worker の登録に成功しました。スコープ: ${registration.scope}`)
    }).catch((error) => {
      // 登録失敗
      // console.log(`Service Worker の登録に失敗しました。${error}`)
    })
}
