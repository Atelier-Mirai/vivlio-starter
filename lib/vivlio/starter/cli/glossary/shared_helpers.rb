# frozen_string_literal: true

require 'yaml'

module Vivlio
  module Starter
    module CLI
      # Glossary 関連コマンドで共通利用するユーティリティ群
      module GlossarySharedHelpers
        private

        # 指定コマンド名で glossary.yml の存在を検証しパスを返す
        def glossary_path_or_exit(command_label)
          path = File.join('config', 'glossary.yml')
          unless File.file?(path)
            warn "[#{command_label}] #{path} が見つかりません"
            exit 1
          end
          path
        end

        # glossary.yml を読み込み、terms セクション付きの Hash を返す
        def load_glossary(path)
          (YAML.load_file(path) || {}).tap do |hash|
            hash['terms'] ||= []
          end
        end

        # lint / fix コマンドが扱いやすい形に terms を整形して取得する
        def load_glossary_terms(glossary_path)
          glossary = load_glossary(glossary_path)
          (glossary['terms'] || []).map do |t|
            {
              key: t['key'],
              name: t['name'],
              abbr: t['abbr'],
              first_full_form: !t['first_full_form'].nil?,
              aliases: (t['aliases'] || []).uniq,
              style: t['style']
            }
          end
        end

        # lint / fix コマンドが対象とする Markdown ファイル一覧を返す
        def collect_markdown_files
          Dir.glob(File.join('contents', '**', '*.md'))
        end
      end
    end
  end
end
