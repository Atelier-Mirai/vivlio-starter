# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/glossary/shared_helpers.rb
# ================================================================
# 責務:
#   glossary 系コマンド（lint, fix, add, canonicalize）の共通処理を提供する。
#
# 提供機能:
#   - glossary.yml の読み込み・検証
#   - 用語エントリの正規化
#   - contents/ 以下の Markdown ファイル収集
#   - コードブロック・コメント領域の判定
#
# 用語エントリの構造:
#   - name: 正式名称（例: "HyperText Markup Language"）
#   - abbr: 略称（例: "HTML"）
#   - aliases: 別名リスト（lint で警告される表記）
#   - style: 表記スタイル（english/katakana）
#   - first_full_form: 初出時のフルスペル
# ================================================================

require 'yaml'

module Vivlio
  module Starter
    module CLI
      # glossary コマンド共通ヘルパー
      module GlossarySharedHelpers
        GLOSSARY_RELATIVE_PATH = File.join(Common::CONFIG_DIR, 'glossary.yml')
        GLOSSARY_DISPLAY_PATH = begin
                                  absolute = Common.resolve_path_from_root(GLOSSARY_RELATIVE_PATH)
                                  Common.relative_path_from_root(absolute) || absolute
        end

        module_function

        # 指定コマンド名で glossary.yml の存在を検証しパスを返す
        def glossary_path_or_exit(command_label)
          path = Common.resolve_path_from_root(GLOSSARY_RELATIVE_PATH)
          display_path = Common.relative_path_from_root(path) || GLOSSARY_DISPLAY_PATH

          unless path && File.file?(path)
            warn "[#{command_label}] #{display_path} が見つかりません"
            exit 1
          end
          path
        end

        # glossary.yml を読み込み、terms セクション付きの Hash を返す
        # YAML として壊れている場合や Hash でない場合はエラー終了する
        def load_glossary(path)
          text = File.read(path, encoding: 'UTF-8')
          data = YAML.safe_load(text, permitted_classes: [], aliases: true)

          unless data.is_a?(Hash)
            warn "[glossary] YAML の形式が不正です（Hash ではありません）: #{GLOSSARY_DISPLAY_PATH}"
            exit 1
          end

          data['terms'] ||= []
          data
        rescue StandardError => e
          warn "[glossary] YAML の読み込みに失敗しました: #{GLOSSARY_DISPLAY_PATH} (#{e.class}: #{e.message})"
          exit 1
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
