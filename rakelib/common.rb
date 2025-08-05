require 'fileutils'
require 'json'
require 'yaml'

# 書籍ビルドシステムの共通モジュール
module BookBuild
  # 設定
  CONTENTS_DIR      = 'contents'
  STYLESHEETS_DIR   = 'stylesheets'
  IMAGES_DIR        = 'images'
  CODES_DIR         = 'codes'
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
    chapter_dir = filename.sub(/\.md$/, '')
    
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
    # ARGVからRakeタスク名とオプションを除外した引数を取得
    files_arg = ARGV.reject { |a| a =~ /^(rake|build|--)/i }
    
    # 引数をタスクとして解釈されないようにダミータスクを作成
    files_arg.each do |arg|
      task_name = arg.to_sym
      if Rake::Task.task_defined?(task_name)
        Rake::Task[task_name].clear
      end
      Rake::Task.define_task(task_name) {}
    end
    
    files_arg
  end
end
