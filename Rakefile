# 電気・電子技術への招待 ～古代の叡智から現代AIまで～ ビルドシステム
# メインRakefile - 機能別に分割されたタスクを統合
# rake help で利用可能なタスク一覧を表示

# デフォルトタスク - ビルドを実行
desc "電子書籍ビルドの全工程を実行します"
task :default => :build

# 全てのタスクは rakelib ディレクトリの各ファイルに分割されています
# - common.rb: 共通モジュールと設定
# - preprocess.rake: 前処理関連タスク
# - convert.rake: HTML変換関連タスク
# - css.rake: CSS生成関連タスク
# - toc.rake: 目次生成関連タスク
# - pdf.rake: PDF生成関連タスク
# - build.rake: ビルド関連タスク
# - utility.rake: ユーティリティタスク

