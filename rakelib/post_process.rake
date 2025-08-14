require 'json'
require 'yaml'
require_relative 'common'

# 指定HTMLファイルに対して、
# - replace_rules(JSONの配列) に基づく置換を適用
# 結果を書き戻し、置換件数を返す
# 戻り値: { changed: true/false, replacements: Integer }
def process_html_file(html_file, replace_rules)
  html_content     = File.read(html_file, encoding: 'utf-8')
  original_content = html_content.dup
  file_replacements = 0

  # 置換ルール適用
  if replace_rules
    replace_rules.each do |item|
      next unless item.is_a?(Hash) && item.key?('f') && item.key?('r')

      pattern         = Regexp.new(item['f'])
      replacement_str = item['r'].dup
      matches_found   = 0

      html_content.gsub!(pattern) do |match|
        matches_found += 1
        m      = pattern.match(match)
        result = replacement_str.dup
        if m && m.captures.any?
          m.captures.each_with_index { |cap, i| result.gsub!("$#{i + 1}", cap.to_s) }
        end
        result
      end

      if matches_found > 0
        file_replacements += matches_found
        BookBuild.log_info("パターン '#{item['f']}' → #{matches_found}個の置換")
      end
    end
  end

  changed = html_content != original_content
  if changed
    File.write(html_file, html_content, encoding: 'utf-8')
  end

  { changed: changed, replacements: file_replacements }
end



desc "HTMLファイルのポスト置換処理を行います"
task :post_process do |t, _args|
  # 引数を取得
  args    = BookBuild.process_args('post_process')
  files   = args[:files]
  options = args[:options]

  # 引数があれば .html のみを対象にする
  html_files = if files.any?
    files.map { |f| f.end_with?('.html') ? f : "#{f}.html" }.uniq
  else
    Dir.glob('*.html')
  end

  # file_typeを取得して、<body> にクラスを付与
  html_files.each do |html_file|
    content   = File.read(html_file, encoding: 'utf-8')
    file_type = BookBuild.get_file_type(html_file)
    updated   = content.gsub('<body>', "<body class=\"#{file_type}\">")
    File.write(html_file, updated, encoding: 'utf-8')
    BookBuild.log_info("#{html_file}: <body>→class追加(#{file_type})")
  end

  # 置換ルールの読み込み（YAMLのみ）
  replace_rules = nil
  target_yml = '_post_replace_list.yml'

  if File.exist?(target_yml)
    begin
      yml_content = File.read(target_yml, encoding: 'utf-8')
      parsed = YAML.safe_load(yml_content, permitted_classes: [], aliases: true)
      replace_rules = parsed.is_a?(Array) ? parsed : nil
      BookBuild.log_error('エラー: YAMLファイルは置換オブジェクト配列である必要があります') unless replace_rules
      BookBuild.log_info("置換ルール: #{File.basename(target_yml)} を使用")
    rescue => e
      BookBuild.log_error("YAMLの読み込みに失敗: #{e.message}")
    end
  else
    BookBuild.log_error("置換ルールYAMLが見つかりません: #{target_yml}")
  end

  # 置換ルールをもとにHTMLファイルの置換処理
  total_replacements = 0
  html_files.each do |html_file|
    BookBuild.log_action("処理中: #{html_file}")
    result = process_html_file(html_file, replace_rules)
    if result[:changed]
      total_replacements += result[:replacements]
      BookBuild.log_success("#{html_file}: #{result[:replacements]}個の置換を反映")
    else
      BookBuild.log_info("#{html_file}: 変更なし")
    end
  end

  # 行番号を追加(Prism.js対応)
  BookBuild.log_action('ソースコードに行番号を追加中...')
  Rake::Task['prism:lines_all'].invoke

  BookBuild.log_success("ポスト置換処理完了 (合計: #{total_replacements}個の置換)")
end