# ヘルプ表示
desc "タスクの使い方を表示します"
task :help do
  print <<~HELP
    📚 Vivliostyle - Build System
    利用可能なタスク一覧:
      rake init                   - プロジェクト初期化
      rake create <filename>      - 新しい章を作成
      rake preprocess             - 前処理（全ファイル）
      rake preprocess <files...>  - 前処理（指定ファイル）
      rake convert                - HTML変換（全ファイル）
      rake convert <files...>     - HTML変換（指定ファイル）
      rake css:chapter            - 章ごとのCSS生成
      rake toc                    - 目次生成
      rake entries                - entries.js生成
      rake images                 - 画像ディレクトリ生成
      rake build                  - 全ファイルビルド
      rake build <files...>       - 指定ファイルのみビルド
      rake pdf                    - PDF生成
      rake open                   - 生成PDFを開く
      rake clean                  - クリーンアップ
      rake vivliostyle            - vivliostyle.config.js生成
      rake vivliostyle[true]      - バックアップ付きで生成
      rake vivliostyle_diff       - 設定の差分表示です
  HELP
end
