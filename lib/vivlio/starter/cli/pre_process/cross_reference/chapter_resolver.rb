# frozen_string_literal: true

require_relative '../../common'
require_relative '../../post_process/heading_processor'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        module CrossReference
          # 章番号の抽出と表示用番号の解決を担当
          module ChapterResolver
            module_function

            # ファイル名から章番号を抽出
            def extract_number(filename)
              basename = File.basename(filename, '.*')
              match = basename.match(/^(\d+)/)
              match ? match[1] : '0'
            end

            # メイン章の順序を取得
            def main_chapter_order
              # 1. build コマンド側から一時的な章リストが指定されている場合はそれを優先
              override = PostProcessCommands::HeadingProcessor.chapter_tokens_override
              if override && !override.empty?
                tokens = PostProcessCommands::HeadingProcessor.normalize_and_filter_tokens(override)
                return tokens if tokens && !tokens.empty?
              end

              # 2. config/book.yml の chapters 設定を優先
              tokens = PostProcessCommands::HeadingProcessor.configured_main_chapter_tokens
              return tokens if tokens && !tokens.empty?

              # 3. フォールバック: contents/ 配下の .md からメイン章を自動検出
              md_tokens = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |p| File.basename(p, '.md') }
              seen = {}
              filtered = []

              md_tokens.each do |entry|
                token = PostProcessCommands::HeadingProcessor.normalize_chapter_token(entry)
                next unless token
                next unless PostProcessCommands::HeadingProcessor.main_chapter_token?(token)
                next if seen[token]

                seen[token] = true
                filtered << token
              end

              filtered.sort_by { |token| Common.get_chapter_number(token).to_i }
            end

            # 表示用の章番号を取得
            def display_number(filename)
              chapter_number = extract_number(filename)
              chapter_number_i = chapter_number.to_i

              range = PostProcessCommands::HeadingProcessor::MAIN_CHAPTER_RANGE
              return chapter_number unless range.include?(chapter_number_i)

              chapter_token = File.basename(filename, File.extname(filename))
              order = main_chapter_order
              if (idx = order.index(chapter_token))
                return (idx + 1).to_s
              end

              (chapter_number_i - 10).to_s
            end
          end
        end
      end
    end
  end
end
