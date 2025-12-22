# frozen_string_literal: true

require 'pdf-reader'

# 引数として受け取ったPDFファイルからテキストを抽出し、テキストファイルに保存する関数
def extract_text_and_save(pdf_path)
  # PDFファイルの存在を確認
  unless File.exist?(pdf_path)
    puts "エラー: 指定されたPDFファイルが見つかりません: #{pdf_path}"
    return
  end

  begin
    reader = PDF::Reader.new(pdf_path)
    text_content = ''
    reader.pages.each do |page|
      text_content += page.text
    end

    # 出力ファイル名を生成
    output_txt_path = pdf_path.sub(/\.pdf$/i, '.txt')

    # 抽出したテキストをファイルに書き込む
    File.open(output_txt_path, 'w:UTF-8') do |file|
      file.write(text_content)
    end

    puts "PDFが正常にテキストに変換されました: #{output_txt_path}"
  rescue StandardError => e
    puts "変換中にエラーが発生しました: #{e.message}"
  end
end

# コマンドライン引数を処理
if ARGV.length != 1
  puts '使い方: ruby your_script.rb <input_pdf_file>'
  exit
end

input_pdf_file = ARGV[0]
extract_text_and_save(input_pdf_file)
