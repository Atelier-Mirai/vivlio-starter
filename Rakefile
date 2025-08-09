# 電気・電子技術への招待 ～古代の叡智から現代AIまで～ ビルドシステム


# 標準出力を抑制するためのモンキーパッチ（デバッグ中は無効化）
module Kernel
  # 元のputsをエイリアス
  alias_method :original_puts, :puts unless method_defined?(:original_puts)
  
  def puts(*args)
    # エラーメッセージや重要なメッセージは表示
    if args.any? { |arg| arg.to_s =~ /(❌|⚠️|error|エラー|失敗)/i }
      original_puts(*args)
    # それ以外はverboseモードでのみ表示
    elsif ARGV.include?('-v') || ARGV.include?('--verbose')
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

# 全てのタスクは rakelib ディレクトリの各ファイルに分割されています
# - common.rb: 共通モジュールと設定
# - preprocess.rake: 前処理関連タスク
# - convert.rake: HTML変換関連タスク
# - css.rake: CSS生成関連タスク
# - toc.rake: 目次生成関連タスク
# - pdf.rake: PDF生成関連タスク
# - build.rake: ビルド関連タスク
# - utility.rake: ユーティリティタスク
