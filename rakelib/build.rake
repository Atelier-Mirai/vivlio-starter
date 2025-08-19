require_relative 'common'

# 責務: サブタスクを同一プロセスで実行しつつ、一時的な ARGV 差し替えで引数汚染を防ぐ
def __run_task_with_argv(task_name, argv_override = nil)
  __orig_argv = ARGV.dup
  ARGV.replace(argv_override) if argv_override
  # Ensure the task can run multiple times within the same process
  task = Rake::Task[task_name]
  task.reenable
  task.invoke
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

# 責務: PDF のページ数を取得（フルビルド内での利用を想定）
def page_count(file)
  return nil unless File.exist?(file)

  # pdfinfo 直接呼び出し
  if system('which pdfinfo >/dev/null 2>&1')
    info = `pdfinfo "#{file}" 2>/dev/null`
    pages = info[/^Pages:\s+(\d+)/i, 1]
    return pages if pages
  end

  nil
end

# 責務: モード（files/all）別のビルド手順を一元管理する単一の真実源
TASKS_FOR = {
  files: %w[pre_process convert post_process entries],
  all:   %w[pre_process convert post_process entries]
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

  # フルビルド時の事前ステップ（Step 1）: 02-preface を単独ビルド → ページ数取得
  if mode == :all
    # Step 0: まずはクリーンアップを実行
    BookBuild.log_action("[Step 0] クリーンアップを実行します…")
    begin
      Rake::Task['clean'].reenable
      Rake::Task['clean'].invoke
    rescue => e
      BookBuild.log_warn("[Step 0] クリーンアップでエラー: #{e}")
    end

    # Step 1: 02-preface のみ先行ビルド
    BookBuild.log_action("[Step 1] 前書き (02-preface) のみ先行ビルドを実行します…")
    begin
      # 02-preface のみを対象に、通常の files モードと同じ下位タスクを実行
      __run_tasks(TASKS_FOR[:files], ['02-preface'])
      __run_task_with_argv('pdf', [])

      # 出力 PDF リネームとページ数取得
      pdf_config   = BookBuild::CONFIG['pdf'] || {}
      output_pdf   = pdf_config['output_file'] || 'output.pdf'
      preface_pdf  = '02-preface.pdf'
      if File.exist?(output_pdf)
        BookBuild.log_action("preface PDF をリネームしています: #{output_pdf} → #{preface_pdf}")
        FileUtils.rm_f(preface_pdf)
        FileUtils.mv(output_pdf, preface_pdf)
        # ページ数を取得
        pages = page_count(preface_pdf)
        pages ?
          BookBuild.log_success("ページ数: #{pages} (#{preface_pdf})") :
          BookBuild.log_warn("ページ数の取得に失敗しました: #{preface_pdf}")
      else
        BookBuild.log_warn("出力PDFが見つかりません: #{output_pdf}")
      end
    rescue => e
      BookBuild.log_warn("[Step 1] 前書き先行ビルドでエラー: #{e}")
    end

    # Step 2: 付録 (91〜97で始まる章) をビルドし、結合HTMLを作成
    BookBuild.log_action("[Step 2] 付録章 (91〜97で始まる章) をビルドします…")
    begin
      # contents/ 配下から 91〜97 で始まる .md を探索し、ベース名をビルド対象にする
      appendix_paths   = Dir[File.join('contents', '{91,92,93,94,95,96,97}-*.md')]
      appendix_targets = appendix_paths.map { |p| File.basename(p, '.md') }.uniq.sort

      if appendix_targets.empty?
        BookBuild.log_warn('[Step 2] 付録候補(91〜97)が見つかりません。Step 2 をスキップします。')
      else
        BookBuild.log_info("[Step 2] 対象: #{appendix_targets.join(', ')}")
        # HTML生成（pdfはここでは未実施）
        __run_tasks(TASKS_FOR[:files], appendix_targets)

        # 以下とほぼ等価
        # verbose = BookBuild.verbose? ? ' -v' : ''
        # appendix_targets.each do |target|
        #   system("rake pre_process #{target}#{verbose}")  or raise "[Step 2] pre_process failed: #{target}"
        #   system("rake convert #{target}#{verbose}")      or raise "[Step 2] convert failed: #{target}"
        #   system("rake post_process #{target}#{verbose}") or raise "[Step 2] post_process failed: #{target}"
        # end

        # 付録HTMLを結合して 90-appendices.html を生成
        BookBuild.log_action("[Step 2] 付録HTMLを結合して 90-appendices.html を生成します…")
        Rake::Task['merge:appendices'].reenable
        Rake::Task['merge:appendices'].invoke
        BookBuild.log_success("[Step 2] 90-appendices.html を生成しました")
      end
    rescue => e
      BookBuild.log_warn("[Step 2] 付録ビルド/結合でエラー: #{e}")
    end

    # Step 3: 章をビルドし、各HTMLを生成（11-*.md 〜 89-*.md が対象）
    # 例: rake build 11-gift -> 11-gift.html を生成
    BookBuild.log_action("[Step 3] 章をビルドします…")
    begin
      # contents/ 配下の *.md を走査し、先頭の番号が 11..89 のものを対象にする
      chapter_paths = Dir[File.join('contents', '*.md')]
      chapter_targets = chapter_paths
        .map { |p| File.basename(p, '.md') }
        .select { |name| name =~ /\A(\d+)-/ && (11..89).include?($1.to_i) }
        .uniq
        .sort

      if chapter_targets.empty?
        BookBuild.log_warn('[Step 3] 章が見つかりません。Step 3 をスキップします。')
      else
        BookBuild.log_info("[Step 3] 対象: #{chapter_targets.join(', ')}")
        # HTML生成（pdfはここでは未実施）
        __run_tasks(TASKS_FOR[:files], chapter_targets)
        BookBuild.log_success("[Step 3] 章 HTML を生成しました")
      end
    rescue => e
      BookBuild.log_warn("[Step 3] エラー: #{e}")
    end

    # Step 4: 目次の生成（11-*.html 〜 89-*.html ＋ 90-appendices.html を対象）
    BookBuild.log_action("[Step 4] 目次(03-toc.html)を生成します…")
    begin
      # 章HTML（11..89）を列挙
      chapter_htmls = Dir.glob('*.html')
                         .select { |f| f =~ /\A(\d+)-.*\.html\z/ && (11..89).include?($1.to_i) }
                         .sort
      # 付録結合HTMLを追加（存在する場合）
      appendix_html = '90-appendices.html'
      targets_for_toc = chapter_htmls
      targets_for_toc << appendix_html if File.exist?(appendix_html)

      if targets_for_toc.empty?
        BookBuild.log_warn('[Step 4] 対象HTMLが見つかりません。Step 4 をスキップします。')
      else
        BookBuild.log_info("[Step 4] 対象: #{targets_for_toc.join(', ')}")
        # toc タスクに対象HTMLを引数として渡して実行
        __run_task_with_argv('toc', targets_for_toc)
        BookBuild.log_success('[Step 4] 03-toc.html を生成しました')
      end
    rescue => e
      BookBuild.log_warn("[Step 4] 目次生成でエラー: #{e}")
    end


  end

  # タスクの実行
  if mode == :files
    __run_tasks(TASKS_FOR[mode], argv)
    __run_task_with_argv('pdf', [])
  end

  # 完了メッセージ
  BookBuild.log_success(mode == :files ? "指定ファイルのビルド完了" : "全ファイルのビルド完了")

  # クリーンアップ
  # BookBuild.log_action("クリーンアップを実行しています...")
  # Rake::Task['clean'].invoke

  # PDFを開く（暫定措置: フルビルドでは開かない）
  # TODO: Step1 での一時PDF運用を整理後、フルビルド時の open を復帰する
  if mode == :files
    __open_pdf_if_macos
  else
    BookBuild.log_info('フルビルドのため自動オープンを一時停止中（暫定措置）')
  end
end

# 全体ビルド（デフォルトタスク）
desc "全体ビルドを実行します（前処理→変換→目次生成→entries.js生成→PDF生成→クリーンアップ→PDFを開く）"
task :default => [:build]
