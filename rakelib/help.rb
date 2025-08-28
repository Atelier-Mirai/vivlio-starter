# ヘルプ表示
print <<~HELP
  📚 Vivlio Starter - Build System

  主なコマンド:
    vs build                       - 全ファイルをビルド
    vs build <chapter_name>        - 指定した章のみをビルド
    vs open                        - 生成されたPDFを開く(macOS専用)
    vs pdf:compress                - 生成されたPDFを圧縮

    # ビルドオプション:
    --high                # 高画質でビルド（画像の品質優先）
    --medium              # 標準画質でビルド（デフォルト）
    --low                 # 低画質でビルド（ファイルサイズ優先）
    --no-resize           # 画像のリサイズ/最適化をスキップ
    --no-compress         # PDFの圧縮をスキップ
    --no-clean            # 中間ファイルのクリーンアップをスキップ
    -v                    # 詳細な出力を表示

  章の管理:
    vs create <chapter_name>       - 新しい章を作成
    vs delete <chapter_name>       - 指定した章を削除
    vs rename <old> <new>          - 章名・付録名/番号を変更
                                    （例: 11-install → 12-setup, 21 → 32）
    vs renumber                    - 章番号・付録番号を整列
    vs clean                       - ビルド生成物をクリーンアップ

  ヘルプ:
    vs help                        - このヘルプを表示
    vs --version                   - バージョン情報を表示
HELP


    # 内部タスク:
    #   vs pre_process [files...]      - 前処理を実行
    #   vs convert [files...]          - MarkdownをHTMLに変換
    #   vs post_process [files...]     - 後処理を実行
    #   vs toc                         - 目次を生成
    #   vs entries                     - entries.jsを生成
    #   vs config                      - vivliostyle.config.jsを生成
    #   vs merge:appendices            - 付録を単一HTMLに結合

    #   vs create:titlepage            - 表紙ページを生成
    #   vs create:colophon             - 奥付を生成
    #   vs titlephon                   - 表紙と奥付を一括生成

    #   vs resize [--high|--medium|--low] [DIR=.] - 画像をWebPに一括リサイズ/変換

