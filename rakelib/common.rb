require 'fileutils'
require 'json'
require 'yaml'

# 書籍ビルドシステムの共通モジュール
module BookBuild
  # 設定
  CONTENT_DIR       = 'content'
  STYLESHEETS_DIR   = 'stylesheets'
  IMAGES_DIR        = 'images'
  VFM_COMMAND       = 'vfm'
  POST_REPLACE_FILE = '_postReplaceList.json'
  
  # ファイルタイプを判定
  def self.get_file_type(filename)
    case filename
    when /^00-/
      'preface'
    when /^01-toc/
      'toc'
    when /^1[1-9]-/, /^[2-8][0-9]-/
      'chapter'
    when /^9[1-7]-/
      'appendix'
    when /^98-/
      'postface'
    when /^99-colophon/
      'colophon'
    else
      'chapter'  # デフォルト
    end
  end
  
  # フロントマターを生成
  def self.generate_frontmatter(file_type, chapter_num = nil, existing_frontmatter = {})
    # ファイルタイプに対応する基本スタイルシート
    stylesheets = ["#{file_type}.css"]

    # チャプター固有のCSSを追加
    if file_type == 'chapter' && chapter_num
      stylesheets << "#{chapter_num}.css"
    end
    
    # 新しいフロントマターのベースを作成
    new_frontmatter = {
      'link' => stylesheets.map { |css| 
        { 'rel' => 'stylesheet', 'href' => "stylesheets/#{css}" }
      },
      'lang' => 'ja'
    }
    
    # 既存のフロントマターと新しいフロントマターを併合
    merged_frontmatter = {}
    
    # 既存のフロントマターをベースにする
    merged_frontmatter = existing_frontmatter.dup
    
    # 新しいフロントマターを適用
    new_frontmatter.each do |key, value|
      if key == 'link' && merged_frontmatter['link']
        # linkは配列なので特別処理
        # 既存のリンクを保持しつつ、新しいリンクを追加
        existing_links = merged_frontmatter['link']
        new_links = value
        
        # 重複しないようにマージ
        merged_frontmatter['link'] = existing_links + new_links.reject { |new_link|
          existing_links.any? { |existing_link|
            existing_link['href'] == new_link['href']
          }
        }
      else
        # その他のキーは上書き
        merged_frontmatter[key] = value
      end
    end
    
    merged_frontmatter
  end
  
  # 画像パスを修正
  def self.fix_image_paths(content, filename)
    base_name = filename.sub(/\.md$/, '')
    chapter_dir = base_name.sub(/^(\d+)-.*/, '\1-\2')
    
    # ![alt](image.jpg) → ![alt](images/11-chapter/image.jpg)
    content.gsub(/!\[(.*?)\]\((?!https?:\/\/)(.*?)\)/) do
      alt_text = $1
      image_path = $2
      
      # 既に images/ で始まる場合はそのまま
      if image_path.start_with?('images/')
        "![#{alt_text}](#{image_path})"
      else
        "![#{alt_text}](images/#{chapter_dir}/#{image_path})"
      end
    end
  end
  
  # 引数処理用ヘルパー
  def self.process_args
    files_arg = ARGV[1..-1]
    files_arg.each { |arg| Rake::Task[arg.to_sym].clear if Rake::Task.task_defined?(arg.to_sym) }
    files_arg
  end
end
