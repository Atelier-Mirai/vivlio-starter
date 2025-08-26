# ヘルプ表示
desc "タスクの使い方を表示します"
task :help do
  print <<~HELP
    📚 Vivliostyle - Build System
    利用可能なタスク一覧:
      rake init                    - プロジェクト初期化
      rake build                   - 全ファイルビルド
      rake build <files...>        - 指定ファイルのみビルド
      rake open                    - 生成PDFを開く（= open:pdf）

      rake create <chapter_name>   - 新しい章を作成
      rake delete <chapter_name>   - 章を削除
      rake renumber <n1> <n2>      - 章番号を変更（rename の別名）
      rake renumber                - 章番号を整列
      rake rename <old> <new>      - 章名/番号を変更（例: 81-install → 81-introduction, 81 → 72）

      rake config                  - vivliostyle.config.jsを生成
      vs config                    - 上記の短縮形（推奨）

      ## 以下は内部タスク
      rake preprocess              - 前処理（全ファイル）
      rake preprocess <files...>   - 前処理（指定ファイル）
      rake convert                 - HTML変換（全ファイル）
      rake convert <files...>      - HTML変換（指定ファイル）
      rake toc                     - 目次生成
      rake entries                 - entries.js生成
      rake pdf                     - PDF生成
      rake clean                   - クリーンアップ
  HELP
end
