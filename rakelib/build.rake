require_relative 'common'
require 'hexapdf'

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

# 責務: 対象PDF全ページのフッター中央にローマ小文字のページ番号を描画（紙面に上書き）
# 引数 options: { margin_bottom: 24, font: 'Helvetica', size: 10, color: [0,0,0] }
def overlay_roman_page_numbers!(pdf_path, options = {})
  return false unless File.exist?(pdf_path)
  opts = { margin_bottom: 24, font: 'Helvetica', size: 10, color: [0, 0, 0] }.merge(options)

  begin
    doc = HexaPDF::Document.open(pdf_path)
    total = doc.pages.count

    mm = 72.0 / 25.4
    (0...total).each do |i|
      page = doc.pages[i]
      media_box = page.box(:media)
      width  = media_box.width
      # 下からの余白 + 指定 + 3mm 上へ
      y = media_box.bottom + opts[:margin_bottom] + (3 * mm)
      text = to_roman_lower(i + 1)

      canvas = page.canvas(type: :overlay)
      # 1) 下部25mmを白塗り（既存のページ番号を隠す）
      canvas.save_graphics_state
      # RGBの白(浮動小数 1.0) + 不透明 ※整数1は 1/255 となりほぼ黒になるため注意
      canvas.fill_color(1.0, 1.0, 1.0)
      canvas.opacity(fill_alpha: 1.0, stroke_alpha: 1.0)
      canvas.rectangle(media_box.left, media_box.bottom, width, 25 * mm)
      canvas.fill
      canvas.restore_graphics_state

      # 2) ページ番号描画設定
      canvas.font(opts[:font], size: opts[:size])
      canvas.fill_color(*opts[:color])
      # 文字列幅の簡易見積もりで中央寄せ（Helvetica の平均幅 ~0.5em を仮定）
      est_text_width = text.length * opts[:size] * 0.5
      x = media_box.left + (width / 2.0) - (est_text_width / 2.0)
      # 奇数/偶数で水平オフセット
      if ((i + 1) % 2) == 1
        # 奇数ページ: 4mm 左へ
        x -= 4 * mm
      else
        # 偶数ページ: 6mm 右へ
        x += 6 * mm
      end
      canvas.text(text, at: [x, y])
    end

    doc.write(pdf_path, optimize: true)
    true
  rescue => e
    BookBuild.log_warn("[Step 6] ページ番号のオーバーレイ描画でエラー: #{e}")
    false
  end
end

# 責務: 整数をローマ数字（小文字）に変換（1..3999までを想定）
def to_roman_lower(n)
  return '' if n <= 0
  mapping = [
    [1000, 'm'], [900, 'cm'], [500, 'd'], [400, 'cd'],
    [100, 'c'], [90, 'xc'], [50, 'l'], [40, 'xl'],
    [10, 'x'], [9, 'ix'], [5, 'v'], [4, 'iv'], [1, 'i']
  ]
  res = ''
  mapping.each do |val, sym|
    count, n = n.divmod(val)
    res << sym * count
  end
  res
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

# 責務: HexaPDF で PageLabels を設定する
# - 先頭（本文+付録）: アラビア数字 1, 2, 3, ...
# - frontmatter（末尾）: ローマ小文字 i, ii, iii, ...
# 引数 body_pages: 本文+付録のページ数（frontmatter の開始インデックス= body_pages）
def apply_page_labels_hexapdf(pdf_path, body_pages)
  return false unless File.exist?(pdf_path)
  begin
    doc = HexaPDF::Document.open(pdf_path)
    total = doc.pages.count

    # NumberTree: /PageLabels << /Nums [ startIndex dict ... ] >>
    nums = []

    bp = body_pages.to_i
    if bp <= 0
      # 特殊運用: 対象PDF全体をローマ小文字 i〜 にする（frontmatter.pdf 単独向け）
      nums = [0, { S: :r, St: 1 }]
    else
      # デフォルト: 先頭=アラビア1〜、bp位置からローマ小 i〜
      nums = [0, { S: :D, St: 1 }]
      if bp < total
        nums += [bp, { S: :r, St: 1 }]
      end
    end

    doc.catalog[:PageLabels] = doc.add({ Type: :NumberTree, Nums: nums })
    doc.write(pdf_path, optimize: true)
    true
  rescue => e
    BookBuild.log_warn("[Step 6] HexaPDF によるページラベル設定でエラー: #{e}")
    false
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

# 責務: qpdf で「本文+付録（先頭〜frontmatter直前）」と「末尾frontmatter」を抽出
# 期待: 全体PDFが「chapters... + appendices... + preface + toc」の順である前提
def split_pdf_chapters_then_frontmatter(output_pdf, frontmatter_pages, front_pdf, body_pdf)
  total_pages = (page_count(output_pdf) || '0').to_i
  if total_pages <= 0
    BookBuild.log_warn("[Step 5] 総ページ数の取得に失敗しました: #{output_pdf}")
    return false
  end

  unless system('which qpdf >/dev/null 2>&1')
    BookBuild.log_warn('[Step 5] qpdf が見つかりません。`brew install qpdf` でインストールしてください。')
    return false
  end

  FileUtils.rm_f(front_pdf)
  FileUtils.rm_f(body_pdf)

  body_end = total_pages - frontmatter_pages
  ok1 = ok2 = true

  # 本文・付録を抽出（先頭〜frontmatter直前）
  if body_end > 0
    BookBuild.log_action("[Step 5] 本文・付録を抽出しています (1-#{body_end})…")
    ok1 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" 1-#{body_end} -- "#{body_pdf}"))
  else
    BookBuild.log_warn('[Step 5] 本文側のページがありません。frontmatter が全ページを占めています。')
  end

  # frontmatter を抽出（末尾 frontmatter_pages）
  if frontmatter_pages < total_pages
    start_last = body_end + 1
    BookBuild.log_action("[Step 5] frontmatter を抽出しています (#{start_last}-z)…")
    ok2 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" #{start_last}-z -- "#{front_pdf}"))
  else
    BookBuild.log_warn('[Step 5] frontmatter が全ページを占めています。frontmatter 側のみ生成します。')
  end

  if ok1 && ok2
    BookBuild.log_success("[Step 5] 分割完了: #{front_pdf}, #{body_pdf}")
    true
  else
    BookBuild.log_warn('[Step 5] PDF の分割に失敗しました (qpdf 実行エラー)')
    false
  end
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
    BookBuild.log_action("[Step 4] 目次(03-toc.html / 03-toc.pdf)を生成します…")
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

        # 目次のPDFを生成
        __run_task_with_argv('entries', ['03-toc.html'])
        __run_task_with_argv('pdf', [])

        # output.pdf を 03-toc.pdf にリネーム
        pdf_config   = BookBuild::CONFIG['pdf'] || {}
        output_pdf   = pdf_config['output_file'] || 'output.pdf'
        toc_pdf      = '03-toc.pdf'
        if File.exist?(output_pdf)
          BookBuild.log_action("output.pdf をリネームしています: #{output_pdf} → #{toc_pdf}")
          FileUtils.rm_f(toc_pdf)
          FileUtils.mv(output_pdf, toc_pdf)
        end

        BookBuild.log_success('[Step 4] 03-toc.pdf を生成しました')
      end
    rescue => e
      BookBuild.log_warn("[Step 4] 目次生成でエラー: #{e}")
    end

    # Step 5: 章HTMLをPDF化（前付け+目次+本文）し、frontmatter/chapters に分割
    BookBuild.log_action("[Step 5] 全体PDFを生成し、frontmatter/chapters に分割します…")
    begin
      # ビルド対象HTMLの順序を定義
      toc_html = ['03-toc.html'].select { |f| File.exist?(f) }
      chapter_htmls_for_pdf = Dir.glob('*.html')
                                 .select { |f| f =~ /\A(\d+)-.*\.html\z/ && (11..89).include?($1.to_i) }
                                 .sort
      appendix_html_for_pdf = File.exist?('90-appendices.html') ? ['90-appendices.html'] : []
      targets_for_pdf = chapter_htmls_for_pdf + appendix_html_for_pdf + toc_html

      if targets_for_pdf.empty?
        BookBuild.log_warn('[Step 5] 対象HTMLが見つかりません。Step 5 をスキップします。')
      else
        BookBuild.log_info("[Step 5] 対象: #{targets_for_pdf.join(', ')}")
        __run_task_with_argv('entries', targets_for_pdf)
        __run_task_with_argv('pdf', [])

        pdf_config   = BookBuild::CONFIG['pdf'] || {}
        output_pdf   = pdf_config['output_file'] || 'output.pdf'

        unless File.exist?(output_pdf)
          BookBuild.log_warn("[Step 5] 出力PDFが見つかりません: #{output_pdf}")
        else
          # toc ページ数を算出（02-preface.pdf + 03-toc.pdf の合計）
          toc_pages     = (page_count('03-toc.pdf') || '0').to_i

          if toc_pages <= 0
            BookBuild.log_warn('[Step 5] toc のページ数が 0 です。分割をスキップします。')
          else
            # 本文.pdf と 目次.pdf に分割する
            split_pdf_chapters_then_frontmatter(
              output_pdf,               # 分割元の全体PDFパス
              toc_pages,                # 末尾のフロントマターのページ数
              '03-toc.pdf',             # フロントマター出力先
              'chapters_appendices.pdf' # 本文+付録出力先
            )
          end
        end
      end
    rescue => e
      BookBuild.log_warn("[Step 5] 章PDF化/分割でエラー: #{e}")
    end

    # Step 6: frontmatter.pdf に ローマ小 i〜 のページラベルを設定し、紙面にも描画する
    begin
      # frontmatter.pdf を作成: 02-preface.pdf + (必要なら空白1ページ) + 03-toc.pdf
      preface_pdf      = '02-preface.pdf'
      toc_pdf          = '03-toc.pdf'
      frontmatter_pdf  = 'frontmatter.pdf'

      unless File.exist?(preface_pdf) && File.exist?(toc_pdf)
        BookBuild.log_warn("[Step 6] frontmatter 構成ファイルが見つかりません: #{[preface_pdf, toc_pdf].reject { |f| File.exist?(f) }.join(', ')}")
        raise "必要ファイル不足"
      end

      # 03-toc.pdf を奇数ページ開始にするため、02-preface.pdf のページ数が奇数なら空白1ページを挿入
      insert_blank = false
      begin
        preface_pages = HexaPDF::Document.open(preface_pdf).pages.count
        insert_blank = preface_pages.odd?
      rescue => e
        BookBuild.log_warn("[Step 6] #{preface_pdf} のページ数取得に失敗 (#{e})。空白挿入なしで続行します")
      end

      parts = [preface_pdf]
      blank_tmp = 'blank_frontmatter_insert.pdf'
      if insert_blank
        begin
          # A4 Portrait: 595.28 x 841.89 pt（Step 8 と同等）
          doc = HexaPDF::Document.new
          doc.pages.add([0, 0, 595.28, 841.89])
          doc.write(blank_tmp, optimize: true)
          parts << blank_tmp
          BookBuild.log_info('[Step 6] 03-toc.pdf を奇数開始にするため、空白1ページを挿入します')
        rescue => e
          BookBuild.log_warn("[Step 6] 空白ページPDFの作成に失敗: #{e}。挿入をスキップします")
        end
      end
      parts << toc_pdf

      FileUtils.rm_f(frontmatter_pdf)
      cmd = ['bundle', 'exec', 'hexapdf', 'merge', *parts, frontmatter_pdf].join(' ')
      if system(cmd) && File.exist?(frontmatter_pdf)
        BookBuild.log_success("[Step 6] frontmatter.pdf を生成しました (構成: #{parts.join(' + ')})")
      else
        BookBuild.log_warn('[Step 6] frontmatter.pdf の生成に失敗しました')
        raise 'frontmatter merge failed'
      end

      # 一時ファイルを掃除
      FileUtils.rm_f(blank_tmp) if insert_blank && File.exist?(blank_tmp)

      apply_page_labels_hexapdf('frontmatter.pdf', 0)
      if overlay_roman_page_numbers!('frontmatter.pdf')
        BookBuild.log_success('[Step 6] frontmatter.pdf にローマ小 i〜 を描画しました')
      else
        BookBuild.log_warn('[Step 6] frontmatter.pdf へのローマ小描画をスキップ/失敗')
      end
    rescue => e
      BookBuild.log_warn("[Step 6] ページ番号連番化処理でエラー: #{e}")
    end

    # Step 7: 本扉、扉裏、後書き、奥付を生成する
    begin
      # 本扉（タイトルページ）
      Rake::Task['create:titlepage'].reenable
      Rake::Task['create:titlepage'].invoke
      __run_tasks(TASKS_FOR[:files], ['00-titlepage'])
      __run_task_with_argv('pdf', [])
      FileUtils.rm_f('titlepage.pdf')
      if File.exist?('output.pdf')
        FileUtils.mv('output.pdf', '00-titlepage.pdf')
        BookBuild.log_success('[Step 7] 00-titlepage.pdf を生成しました')
      else
        BookBuild.log_warn('[Step 7] 00-titlepage の output.pdf が見つかりません')
      end

      # 扉裏（法的免責、商標等）
      __run_tasks(TASKS_FOR[:files], ['01-legalpage'])
      __run_task_with_argv('pdf', [])
      FileUtils.rm_f('legalpage.pdf')
      if File.exist?('output.pdf')
        FileUtils.mv('output.pdf', '01-legalpage.pdf')
        BookBuild.log_success('[Step 7] 01-legalpage.pdf を生成しました')
      else
        BookBuild.log_warn('[Step 7] 01-legalpage の output.pdf が見つかりません')
      end

      # 後書き
      __run_tasks(TASKS_FOR[:files], ['98-postface'])
      __run_task_with_argv('pdf', [])
      FileUtils.rm_f('postface.pdf')
      if File.exist?('output.pdf')
        FileUtils.mv('output.pdf', '98-postface.pdf')
        BookBuild.log_success('[Step 7] 98-postface.pdf を生成しました')
      else
        BookBuild.log_warn('[Step 7] 98-postface の output.pdf が見つかりません')
      end

      # 奥付（colophon）
      Rake::Task['create:colophon'].reenable
      Rake::Task['create:colophon'].invoke
      __run_tasks(TASKS_FOR[:files], ['99-colophon'])
      __run_task_with_argv('pdf', [])
      FileUtils.rm_f('colophon.pdf')
      if File.exist?('output.pdf')
        FileUtils.mv('output.pdf', '99-colophon.pdf')
        BookBuild.log_success('[Step 7] 99-colophon.pdf を生成しました')
      else
        BookBuild.log_warn('[Step 7] 99-colophon の output.pdf が見つかりません')
      end
    rescue => e
      BookBuild.log_warn("[Step 7] タイトル/奥付の生成でエラー: #{e}")
    end

    # Step 8: 本扉、扉裏、前書き、目次、本文、付録、後書き、奥付を結合
    BookBuild.log_action("[Step 8] 本扉、扉裏、前書き、目次、本文、付録、後書き、奥付を結合します…")

    files_to_merge = [
      '00-titlepage.pdf',
      '01-legalpage.pdf',
      'frontmatter.pdf',
      'chapters_appendices.pdf',
      '98-postface.pdf',
      '99-colophon.pdf'
    ]

    existing_files = files_to_merge.select { |f| File.exist?(f) }
    missing_files  = files_to_merge - existing_files

    BookBuild.log_warn("[Step 8] 結合対象が見つかりません: #{missing_files.join(', ')}") if missing_files.any?

    if existing_files.empty?
      BookBuild.log_error('[Step 8] 結合対象PDFがありません。処理を中止します')
    else
      # 98-postface.pdf を右ページ開始（奇数ページ開始）に調整
      begin
        postface_name = '98-postface.pdf'
        idx = existing_files.index(postface_name)
        if idx
          # 先行ページ数を合計
          total_before = 0
          existing_files[0...idx].each do |pf|
            begin
              total_before += HexaPDF::Document.open(pf).pages.count
            rescue => e
              BookBuild.log_warn("[Step 8] ページ数取得失敗: #{pf} (#{e})。0ページとして扱います")
            end
          end
          # 次ページ番号が奇数になるよう、合計が偶数である必要がある
          if total_before.odd?
            # 空白ページPDFを作成
            blank_path = 'blank_page.pdf'
            begin
              doc = HexaPDF::Document.new
              # A4 Portrait: 595.28 x 841.89 pt
              doc.pages.add([0, 0, 595.28, 841.89])
              doc.write(blank_path, optimize: true)
              existing_files.insert(idx, blank_path)
              BookBuild.log_info('[Step 8] 98-postface.pdf を奇数開始にするため、空白1ページを挿入しました')
            rescue => e
              BookBuild.log_warn("[Step 8] 空白ページPDFの作成に失敗: #{e}。調整をスキップします")
            end
          end
        end
      rescue => e
        BookBuild.log_warn("[Step 8] 奇数ページ開始調整中にエラー: #{e}")
      end

      BookBuild.log_info("[Step 8] 結合順: #{existing_files.join(' -> ')}")
      FileUtils.rm_f('output.pdf')
      cmd = ['bundle', 'exec', 'hexapdf', 'merge', *existing_files, 'output.pdf'].join(' ')
      merged = system(cmd)
      if merged && File.exist?('output.pdf')
        BookBuild.log_success('[Step 8] output.pdf を生成しました')
      else
        BookBuild.log_error('[Step 8] PDF結合に失敗しました')
      end
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

  # PDFを開く
  __open_pdf_if_macos
end

# 全体ビルド（デフォルトタスク）
desc "全体ビルドを実行します（前処理→変換→目次生成→entries.js生成→PDF生成→クリーンアップ→PDFを開く）"
task :default => [:build]
