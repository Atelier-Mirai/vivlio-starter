# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: convert（Markdown → HTML 変換）
      # ------------------------------------------------
      # - 目的: Markdown を VFM で HTML に変換するコマンド群
      # - 提供コマンド: convert
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb` を参照
      # ================================================================
      module ConvertCommands
        module_function

        CONVERT_DESC = {
          short: 'Markdown を HTML に変換します (Thor)',
          long: <<~DESC
            指定した Markdown（拡張子 .md 省略可）を HTML に変換します。指定が無い場合はカレントディレクトリ直下の全 .md を対象にします。

            例:
              vs convert 11-install
              vs convert 11-install.md 12-tutorial
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'convert [TOKENS...]', CONVERT_DESC[:short]
            long_desc CONVERT_DESC[:long]
            # ================================================================
            # Command: convert（Markdown → HTML 変換）
            # ------------------------------------------------
            # - 概要: 指定 Markdown を VFM で HTML に変換
            # - 入力: *.md（引数未指定時はカレント直下の *.md、README/ROADMAP は除外）
            # - 出力: *.html（同名で拡張子のみ .html に変換）
            # - オプション: --verbose (-v) で詳細ログを出力
            # - 使用コマンド: Common::VFM_COMMAND（config/book.yml の commands.vfm）
            # ================================================================
            def convert(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]
              # Common ベース実装

              # 入出力ディレクトリのベース（常にプロジェクトルート）
              base_dir = '.'

              # md の解決ヘルパー（与えられたトークンを base_dir 配下のパスに正規化）
              normalize_md = lambda do |name|
                n = name.to_s
                n = "#{n}.md" unless n =~ /\.md\z/
                if File.dirname(n) == '.'
                  File.join(base_dir, n)
                else
                  n
                end
              end

              files = Common.normalize_tokens(tokens)

              md_files =
                if files.any?
                  files.map { |f| normalize_md.call(f) }.uniq
                else
                  Dir.glob(File.join(base_dir, '*.md')).reject { |f| File.basename(f) =~ /\A(README|ROADMAP)\.md\z/ }
                end

              md_files.each do |md|
                html = md.sub(/\.md\z/, '.html')
                cmd  = %(#{Common::VFM_COMMAND} "#{md}" > "#{html}")
                ok = system(cmd)
                Common.log_warn("VFM の変換に失敗しました: #{md}") unless ok
              end

              Common.log_success('Markdown→HTML 変換が完了しました')
            end
          end
        end
      end
    end
  end
end