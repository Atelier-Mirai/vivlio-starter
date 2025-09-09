#!/usr/bin/env ruby

require 'date'

filename = 'timings_summary.md'

# ファイル全体を読み込み、データブロックを抽出
data_blocks = []
File.readlines(filename).each_slice(22) do |slice|
  # ブロックの先頭行から日付を抽出
  date_string = slice[0].strip
  
  # 日付文字列が空ではないことを確認
  next if date_string.empty?

  begin
    date = Date.parse(date_string)
    # 日付と、空行を除いたデータ本体をハッシュとして保存
    data_blocks << { date: date, content: slice.first(21) }
  rescue ArgumentError
    # 日付としてパースできない行はスキップ
    $stderr.puts "警告: '#{date_string}' は有効な日付として認識されませんでした。このブロックはスキップします。"
    next
  end
end

# 日付の降順にソート
sorted_blocks = data_blocks.sort_by { |block| block[:date] }.reverse

output_filename = 'timings_summary_sorted.md'
# 新しいファイルに書き出し
File.open(output_filename, 'w') do |file|
  sorted_blocks.each_with_index do |block, index|
    file.print block[:content].join
    file.print "\n" unless index == sorted_blocks.size - 1
  end
end

puts "並び替え結果を '#{output_filename}' に書き出しました。"