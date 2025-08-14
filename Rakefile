# 電気・電子技術への招待 ～古代の叡智から現代AIまで～ ビルドシステム

# Bundler の文脈を自動有効化（bundle exec 省略のため）
begin
  require 'bundler/setup'
rescue LoadError
  # bundler が無い環境でも実行できるように無視
end

# 標準出力を抑制するためのモンキーパッチ（デバッグ中は無効化）
module Kernel
  # 元のputsをエイリアス
  alias_method :original_puts, :puts unless method_defined?(:original_puts)
  
  def puts(*args)
    # エラーメッセージや重要なメッセージは表示
    if args.any? { |arg| arg.to_s =~ /(❌|⚠️|error|エラー|失敗)/i }
      original_puts(*args)
    # それ以外はverboseモードでのみ表示
    elsif defined?(BookBuild) && BookBuild.respond_to?(:verbose?) && BookBuild.verbose?
      original_puts(*args)
    end
  end
end

# rake -T / --tasks を help に差し替える（Rake のトップレベル処理をフック）
Rake::Application.class_eval do
  alias_method :__orig_top_level, :top_level unless method_defined?(:__orig_top_level)

  def top_level
    # -T/--tasks が指定された場合は help タスクを実行して終了
    if respond_to?(:options) && options&.show_tasks && Rake::Task.task_defined?('help')
      Rake::Task['help'].invoke
      exit 0
    end
    __orig_top_level
  end
end


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
