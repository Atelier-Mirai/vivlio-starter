require_relative 'common'

# 責務: サブタスクを同一プロセスで実行しつつ、一時的な ARGV 差し替えで引数汚染を防ぐ
def __run_task_with_argv(task_name, argv_override = nil)
  __orig_argv = ARGV.dup
  ARGV.replace(argv_override) if argv_override
  Rake::Task[task_name].invoke
ensure
  ARGV.replace(__orig_argv)
end

# 責務: 指定配列のサブタスクを順次（直列）実行する実行器
def __run_tasks(task_names, argv_override)
  task_names.each { |t| __run_task_with_argv(t, argv_override) }
end

# 責務: ビルド成果物の確認体験を統一（macOS のみ自動オープン）
def __open_pdf_if_macos
  if RUBY_PLATFORM.include?('darwin')
    Rake::Task['open:pdf'].invoke
  else
    BookBuild.log_info("PDFファイルが生成されました（macOS以外のため自動で開きません）")
  end
end

# 責務: モード（files/all）別のビルド手順を一元管理する単一の真実源
TASKS_FOR = {
  files: %w[preprocess convert entries],
  all:   %w[preprocess convert toc entries]
}

# セクション: エントリーポイント（build）— 引数解釈 → シーケンス実行 → 後処理
# ビルド関連タスク
desc <<~DESC
  書籍をビルドします

  例:
      rake build                     # 全ファイルをビルド
      rake build 02-preface          # 02-preface のみをビルド
      rake build -v                  # 詳細な出力を表示

  オプション:
      -v, --verbose     詳細な出力を表示します
  DESC
task :build do |t, args|
  # コマンドライン引数を取得
  args    = BookBuild.process_args('build')
  files   = args[:files]
  options = args[:options]

  BookBuild.log_action("書籍をビルドしています...")
  
  # モード判定とタスクリスト
  if files.any?
    BookBuild.log_info("指定されたファイルのみ処理します: #{files.join(', ')}")
    mode = :files
    argv = files
  else
    BookBuild.log_info("全ファイルをビルドします")
    mode = :all
    argv = []
  end

  # タスクの実行
  __run_tasks(TASKS_FOR[mode], argv)
  __run_task_with_argv('pdf', [])

  # 完了メッセージ
  BookBuild.log_success(mode == :files ? "指定ファイルのビルド完了" : "全ファイルのビルド完了")

  # クリーンアップ
  # BookBuild.log_action("クリーンアップを実行しています...")
  # Rake::Task['clean'].invoke

  # PDFを開く
  __open_pdf_if_macos
end

# 全体ビルド（デフォルトタスク）
desc "全体ビルドを実行します（前処理→変換→目次生成→entries.js生成→PDF生成→クリーンアップ→PDFを開く）"
task :default => [:build]
