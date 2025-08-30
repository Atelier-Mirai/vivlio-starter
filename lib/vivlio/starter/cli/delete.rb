# frozen_string_literal: true
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: delete（章の削除ユーティリティ）
      # ------------------------------------------------
      # - 目的: 指定章の Markdown・画像ディレクトリ・章別CSS を削除
      # - 提供コマンド: delete
      # - 補足: 確認プロンプト、dry-run対応、force指定に対応
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module DeleteCommands
        extend self
        def included(base)
          # class_option はベース側に定義済み（verbose）
          base.class_eval do
            # delete 本体
            desc 'delete TOKENS...', '指定した章を削除します (Thor)'
            long_desc <<~DESC
              指定した章（単体/複数/範囲）に対して、Markdown・画像ディレクトリ・章別CSSを削除します。

              例:
                vs delete 11-install
                vs delete 11-install.md 12-tutorial
                vs delete 11-21
                vs delete 11 21-31

              オプション:
                --dry-run, -n   実行せずに削除予定のみを表示します（削除の試行）
                --force, -f, -y 確認プロンプト無しで削除を実行します
                --verbose, -v   冗長ログを表示します

              備考:
                ・ユーザー利便性のため、オプションは引数の前後どちらに置いても構いません
                  例: vs delete --force 31-33 / vs delete 31-33 --force
                ・--dry-run と --force を同時指定した場合、--dry-run を優先し --force は無視されます
            DESC
            
            method_option :dry_run, type: :boolean, aliases: '-n', desc: '変更せずに削除予定を表示'
            method_option :force,   type: :boolean, aliases: %w[-f -y], desc: '確認なしで削除'
            # ================================================================
            # Command: delete（章の削除）
            # ------------------------------------------------
            # - 概要: 指定章の文書/画像/CSS を削除
            # - 入力: TOKENS（単体/複数/範囲指定に対応: 11-install, 11-21, 11 21-31 など）
            # - オプション: --dry-run (-n), --force (-f, -y), --verbose (-v)
            # ================================================================
            def delete(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]

              files = Common.normalize_tokens(tokens)
              args_opts = build_options

              # 矛盾オプションの警告: --dry-run と --force が同時指定された場合
              if dry_run?(args_opts) && (args_opts[:force] || args_opts[:f] || args_opts[:y])
                Common.log_warn('--dry-run が指定されているため、--force は無視されます。実ファイルは変更されません。')
              end

              targets = expand_tokens_to_targets(files)
              if targets.empty?
                Common.log_warn("指定に一致する章ファイルが見つかりませんでした: #{files.join(' ')}")
                exit 1
              end

              if dry_run?(args_opts)
                Common.echo_always "\n== Dry Run: 削除予定一覧 =="
                targets.each { |bn| preview_deletions(bn, args_opts) }
                Common.echo_always "\n合計 #{targets.size} 章が対象（dry-run、実ファイルは変更されません）。"
                exit 0
              end

              targets.each do |bn|
                delete_markdown_file(bn, args_opts)
                delete_image_directory(bn, args_opts)
                delete_css_file(bn, args_opts)
              end
            end

            no_commands do
              # Thor の options から Rake 互換のオプションハッシュに変換（delete 専用ローカル実装）
              def build_options
                o = {}
                if respond_to?(:options) && options
                  o[:dry_run] = true if options[:dry_run]
                  o[:n]       = true if options[:dry_run]
                  if options[:force]
                    o[:force] = o[:f] = o[:y] = true
                  end
                end
                o
              end

              # --- 削除処理系 ---
              def confirm_deletion(file_path, options = {})
                opts = options || {}
                return true if opts[:force] || opts[:f] || opts[:y]
                print "⚠️ 本当に #{file_path} を削除しますか？ (y/N): "
                response = $stdin.gets&.chomp&.downcase
                response == 'y' || response == 'yes'
              end

              def delete_markdown_file(filename, options)
                md_file = "#{Common::CONTENTS_DIR}/#{filename}"
                if File.exist?(md_file)
                  if confirm_deletion("文書ファイル: #{md_file}", options)
                    File.delete(md_file)
                    Common.log_success("文書ファイルを削除しました: #{md_file}")
                  else
                    Common.log_info("文書ファイルの削除をスキップしました: #{md_file}")
                  end
                else
                  Common.log_info("文書ファイルは存在しません: #{md_file}")
                end
              end

              def delete_image_directory(filename, options)
                base_filename = filename.gsub(/\.md$/, '')
                image_dir = "#{Common::IMAGES_DIR}/#{base_filename}"
                if Dir.exist?(image_dir)
                  if confirm_deletion("画像ディレクトリ: #{image_dir}", options)
                    FileUtils.remove_dir(image_dir, true)
                    Common.log_success("画像ディレクトリを削除しました: #{image_dir}")
                  else
                    Common.log_info("画像ディレクトリの削除をスキップしました: #{image_dir}")
                  end
                else
                  Common.log_info("画像ディレクトリは存在しません: #{image_dir}")
                end
              end

              def delete_css_file(filename, options)
                chapter_num = Common.get_chapter_number(filename)
                return false unless chapter_num
                css_file = "#{Common::STYLESHEETS_DIR}/#{chapter_num}.css"
                if File.exist?(css_file)
                  if confirm_deletion("CSSファイル: #{css_file}", options)
                    File.delete(css_file)
                    Common.log_success("CSSファイルを削除しました: #{css_file}")
                    true
                  else
                    Common.log_info("CSSファイルの削除をスキップしました: #{css_file}")
                    false
                  end
                else
                  Common.log_info("CSSファイルは存在しません: #{css_file}")
                  false
                end
              end

              # --- トークン展開系 ---
              def list_contents_basenames
                Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |p| File.basename(p) }
              end

              def chapter_number_from_basename(basename)
                (basename[/^(\d+)-/, 1] || nil)&.to_i
              end

              def find_basenames_in_range(from_num, to_num)
                a, b = [from_num.to_i, to_num.to_i].minmax
                list_contents_basenames.select do |bn|
                  n = chapter_number_from_basename(bn)
                  n && n >= a && n <= b
                end
              end

              def expand_token_to_basenames(token)
                t = token.to_s.strip
                return [] if t.empty?
                if t =~ /(\A\d+)-(\d+\z)/
                  return find_basenames_in_range($1, $2)
                end
                if t =~ /\A\d+\z/
                  return list_contents_basenames.select { |bn| bn.start_with?("#{t}-") }
                end
                name = t + '.md'
                path = File.join(Common::CONTENTS_DIR, name)
                File.exist?(path) ? [name] : []
              end

              def expand_tokens_to_targets(tokens)
                Array(tokens).compact.flat_map { |tok| expand_token_to_basenames(tok) }.uniq
              end

              # --- dry-run 系 ---
              def dry_run?(options)
                opts = options || {}
                !!(opts[:dry_run] || opts[:n])
              end

              def preview_deletions(basename, options)
                base = basename.sub(/\.md$/, '')
                md_file = File.join(Common::CONTENTS_DIR, basename)
                img_dir = File.join(Common::IMAGES_DIR, base)
                css_file = nil
                if (num = Common.get_chapter_number(basename))
                  css_file = File.join(Common::STYLESHEETS_DIR, "#{num}.css")
                end
                Common.echo_always "[DRY-RUN] #{base} の削除予定:"
                Common.echo_always "  - 文書:       #{md_file} #{File.exist?(md_file) ? '(exists)' : '(not found)'}"
                Common.echo_always "  - 画像Dir:    #{img_dir} #{Dir.exist?(img_dir) ? '(exists)' : '(not found)'}"
                if css_file
                  Common.echo_always "  - CSS:        #{css_file} #{File.exist?(css_file) ? '(exists)' : '(not found)'}"
                else
                  Common.echo_always "  - CSS:        (対象外)"
                end
              end
            end
          end
        end
      end
    end
  end
end
