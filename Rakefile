# **はじめての技術書づくり ～Vivlio Starter 実践ガイド～**
# Rake: プロジェクトの内部的なビルドタスクやメンテナンススクリプトの実行に向いています。
# Thor: ユーザーが直接使うコマンドラインツールの構築に向いています。

# Bundler の文脈を自動有効化（bundle exec 省略のため）
begin
  # 既に Bundler が読み込まれている場合は二重初期化を避ける
  require 'bundler/setup' unless defined?(Bundler)
rescue LoadError
  # bundler が無い環境でも実行できるように無視
end

# 内部コマンドのリスト
INTERNAL_COMMANDS = %w[
  pre_process
  convert
  post_process
  toc
  entries
  config
  merge:appendices
].freeze

# # 直接 `rake` コマンドの実行を抑止し、CLI 経由のみ許可
# if File.basename($0) == 'rake' && ENV['VS_ALLOW_RAKE'] != '1' && ENV['VS_CLI'] != '1'
#   # 最初の非オプション引数をタスク名として取得
#   requested_task = ARGV.find { |a| a !~ /^-/ } || 'build'
  
#   # 内部コマンドの直接実行をブロック
#   if INTERNAL_COMMANDS.any? { |cmd| requested_task.start_with?(cmd) }
#     warn "❌ このコマンドは内部コマンドのため、直接実行できません。代わりに `vs build` を使用してください。"
#     exit 1
#   end
  
#   warn "❌ このプロジェクトでは rake の直接実行は禁止です。代わりに `vs #{requested_task}` または `vivlio-starter #{requested_task}` を使用してください。"
#   exit 1
# end

#
# デフォルトタスク - ビルドを実行
desc "電子書籍ビルドの全工程を実行します"
task :default => :build

# 全てのタスクは rakelib/ 配下に分割されています（主要ファイル）
# - common.rb: 共通モジュール・設定・ログ
# - options.rb: コマンドラインオプション解析
# - init.rake: プロジェクト初期化
# - preprocess.rake: 前処理（画像パス付与・フロントマター生成・コード取り込み）
# - convert.rake: HTML変換と置換（vfm -> html, post-replace）
# - prism_lines.rake: Prism.js の行番号付与
# - toc.rake: 目次（toc.html）生成
# - entries.rake: 章立て（entries.js）生成
# - pdf.rake: PDF生成・PDFを開く（open:pdf, エイリアス: open）
# - clean.rake: 生成物のクリーンアップ
# - build.rake: 一括ビルド（preprocess → convert → toc → entries → pdf → clean → open）
# - create.rake: 新規章の作成
# - delete.rake: 章の削除
# - renumber.rake: 章番号の変更・整列
# - vivliostyle.rake: vivliostyle.config.js 生成（vivliostyle:generate_config）
# - help.rake: ヘルプ（`rake -T` を置き換え）
