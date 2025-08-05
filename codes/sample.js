// サンプルJavaScriptファイル
function fibonacci(n) {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

function factorial(n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

// メイン処理
function main() {
    console.log("フィボナッチ数列 (10項目):", fibonacci(10));
    console.log("5の階乗:", factorial(5));
}

// 実行
main();
