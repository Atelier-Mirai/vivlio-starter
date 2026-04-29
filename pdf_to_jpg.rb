require 'fileutils'

def process_pdf(pdf_path)
  # 1. 引数とファイルの存在チェック
  if pdf_path.nil? || !File.exist?(pdf_path)
    puts "使用法: ruby pdf_to_jpg.rb <PDFファイル名>"
    return
  end

  # 2. 必要なコマンド (pdftoppm, magick) のチェック
  commands = {
    "pdftoppm" => "poppler-utils",
    "magick"   => "ImageMagick"
  }
  
  commands.each do |cmd, pkg|
    unless system("which #{cmd} > /dev/null 2>&1")
      puts "エラー: '#{cmd}' が見見つかりません。#{pkg} をインストールしてください。"
      return
    end
  end

  # 3. パス設定
  base_name   = File.basename(pdf_path, ".*")
  output_dir  = "#{base_name}_images"
  final_pdf   = "#{base_name}_rasterized.pdf"
  
  FileUtils.mkdir_p(output_dir)

  puts "--- STEP 1: PDFを画像に分解中 (pdftoppm) ---"
  # 高画質を維持するため 300dpi で抽出
  # pdftoppmはページ数に応じて自動で 01, 02 と桁を揃えてくれるのでソートが崩れません
  # 600dpiに変更
  extract_cmd = "pdftoppm -jpeg -r 600 -sep _ \"#{pdf_path}\" \"#{output_dir}/page\""
  # extract_cmd = "pdftoppm -jpeg -r 300 -sep _ \"#{pdf_path}\" \"#{output_dir}/page\""
  # PNG版のコマンド例（もし試すなら）
  # extract_cmd = "pdftoppm -png -r 600 -sep _ \"#{pdf_path}\" \"#{output_dir}/page\""
  
  if system(extract_cmd)
    puts "画像の抽出に成功しました。"
  else
    puts "エラー: 画像の抽出に失敗しました。"
    return
  end

  puts "--- STEP 2: 画像をPDFに再結合中 (ImageMagick) ---"
  # 画像を1つのPDFにまとめます。-quality 95 を指定
  # output_dir 内の jpg を名前順に結合
  combine_cmd = "magick \"#{output_dir}/page_*.jpg\" -quality 95 \"#{final_pdf}\""
  # combine_cmd = "magick \"#{output_dir}/page_*.png\" -quality 95 -strip \"#{final_pdf}\""
  
  if system(combine_cmd)
    puts "--- すべての工程が完了しました！ ---"
    puts "生成されたPDF: #{final_pdf}"
    
    # オプション: 生成した画像フォルダを削除したい場合は以下を有効にしてください
    # FileUtils.rm_rf(output_dir)
  else
    puts "エラー: PDFの再構築に失敗しました。"
  end
end

# 実行
process_pdf(ARGV[0])