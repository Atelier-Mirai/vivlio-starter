# 章名（スラッグ）変更タスク
require_relative 'common'
require 'fileutils'

# 仕様:
# - 使い方: vs rename <old> <new>
# - <old>, <new> は 例) 81-install / 81-introduction のように「番号-スラッグ」形式
# - 81-install.md など拡張子付きも許容（内部で .md を除去）
# - 対応する images/81-install ディレクトリがあれば images/81-introduction に改名
# - 番号は変更しない（番号が異なる指定はエラー）

desc "指定した章のスラッグ（名前）と必要に応じて番号も変更します (例: vs rename 81-install 72-introduction)"
task :rename do |t, args|
  # 引数を処理
  parsed = BookBuild.process_args('rename')
  files   = parsed[:files] || []
  options = parsed[:options] || {}

  old_arg, new_arg = files.take(2)

  if old_arg.nil? || new_arg.nil?
    puts <<~USAGE
      章のスラッグ（名前）と番号を変更します（番号のみ変更したい場合は vs renumber を推奨）
      使用法: vs rename <旧名> <新名>
      例:
        vs rename 81-install 81-introduction
        vs rename 81-install.md 81-introduction.md
        vs rename 81-install 72-introduction
    USAGE
    exit 1
  end

  # .md 拡張子を許容
  old_name = old_arg.sub(/\.md\z/, '')
  new_name = new_arg.sub(/\.md\z/, '')

  contents_dir = BookBuild::CONTENTS_DIR

  # 受理パターン:
  # 1) NN-slug → NN-slug
  # 2) NN → NN  （番号のみ変更: 既存 slug を自動検出/維持, appendix は新番号に合わせて letter を調整）
  number_only = old_name =~ /^\d{2}\z/ && new_name =~ /^\d{2}\z/

  if number_only
    old_number = old_name
    new_number = new_name
    # 旧番号のMDを一意に特定
    old_md_candidates = Dir.glob(File.join(contents_dir, "#{old_number}-*.md")).sort
    if old_md_candidates.empty?
      BookBuild.log_error("#{old_number}章のファイルが見つかりません")
      exit 1
    elsif old_md_candidates.length > 1
      BookBuild.log_error("#{old_number}章のファイルが複数見つかりました:")
      old_md_candidates.each { |f| BookBuild.log_info("- #{File.basename(f)}") }
      exit 1
    end
    old_md = old_md_candidates.first
    old_basename = File.basename(old_md, '.md')
    old_number2, old_slug = old_basename.split('-', 2)
    # new_slug は基本維持。付録番号(91-97)へ移す場合は appendix-letter を調整
    if new_number.to_i.between?(91, 97) && old_slug =~ /appendix-[a-z]/
      new_letter = BookBuild.appendix_number_to_letter(new_number)
      new_slug = old_slug.sub(/appendix-[a-z]/, "appendix-#{new_letter}")
    else
      new_slug = old_slug
    end
  else
    # パターン: NN-slug 指定
    unless old_name =~ /^\d{2}-.+/ && new_name =~ /^\d{2}-.+/
      BookBuild.log_error("引数は 'NN-slug' または 'NN' 形式で指定してください (例: 81-install / 81)")
      exit 1
    end
    old_number, old_slug = old_name.split('-', 2)
    new_number, new_slug = new_name.split('-', 2)
  end

  old_md = File.join(contents_dir, "#{old_number}-#{old_slug}.md")
  new_md = File.join(contents_dir, "#{new_number}-#{new_slug}.md")

  unless File.exist?(old_md)
    BookBuild.log_error("対象のMarkdownが見つかりません: #{File.basename(old_md)}")
    exit 1
  end

  if File.exist?(new_md)
    BookBuild.log_error("変更先のMarkdownが既に存在します: #{File.basename(new_md)}")
    exit 1
  end

  BookBuild.log_action("章名・番号変更: #{old_number}-#{old_slug} → #{new_number}-#{new_slug}")
  BookBuild.log_info("Markdown: #{File.basename(old_md)} → #{File.basename(new_md)}")

  # 確認プロンプト
  print "  ❓ 章名・番号変更を実行しますか？ (y/N): "
  response = STDIN.gets&.chomp&.downcase
  unless response == 'y' || response == 'yes'
    BookBuild.log_warn("章名・番号変更をキャンセルしました")
    exit 0
  end

  # 1. Markdown のリネーム
  FileUtils.mv(old_md, new_md)
  BookBuild.log_success("Markdownの変更が完了しました")

  # 2. CSS のリネーム（番号が変わる場合）
  old_css = File.join('stylesheets', "#{old_number}.css")
  new_css = File.join('stylesheets', "#{new_number}.css")
  if old_number != new_number && File.exist?(old_css)
    if File.exist?(new_css)
      BookBuild.log_warn("#{File.basename(new_css)} が既に存在するため、CSSファイルは手動で統合してください")
    else
      FileUtils.mv(old_css, new_css)
      BookBuild.update_css_counter(new_css, new_number.to_i)
      BookBuild.log_success("CSSファイルの変更が完了しました")
    end
  end

  # 3. 画像ディレクトリのリネーム（存在する場合）
  old_img_dir = File.join('images', "#{old_number}-#{old_slug}")
  new_img_dir = File.join('images', "#{new_number}-#{new_slug}")

  if File.directory?(old_img_dir)
    if File.exist?(new_img_dir)
      BookBuild.log_warn("#{new_img_dir} が既に存在するため、画像ディレクトリは手動で統合してください")
    else
      FileUtils.mv(old_img_dir, new_img_dir)
      BookBuild.log_success("画像ディレクトリの変更が完了しました: #{File.basename(new_img_dir)}")
    end
  else
    BookBuild.log_info("画像ディレクトリは見つかりませんでした: #{old_img_dir}")
  end

  # 4. 既存生成物のクリーンアップ（旧名に紐づくもの）
  [
    File.join('.', "#{old_number}-#{old_slug}.html")
  ].each do |f|
    if File.exist?(f)
      File.delete(f)
      BookBuild.log_info("#{File.basename(f)} を削除")
    end
  end

  BookBuild.log_success("章名・番号変更が完了しました")
  BookBuild.log_info("変更を反映するには以下を実行してください:")
  BookBuild.log_info("vs build #{new_number}-#{new_slug}")
end
