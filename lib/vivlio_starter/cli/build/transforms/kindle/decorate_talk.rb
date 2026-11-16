# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/decorate_talk.rb
# ================================================================
# 責務:
#   会話文を、アイコンの無い 1 行ずつの形へ直す
# ================================================================

require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 会話文を、アイコンの無い 1 行ずつの形へ直す
      module Transforms::Kindle::DecorateTalk
        module_function

        # 会話文（.talk）を Kindle 向けに劣化させる（talk-display-options-spec.md §2.5）。
        #
        # KFX は flex・::before/::after・var()・丸抜き画像を解さないため、吹き出しを近似せず
        # **style=inline と同じ形（名前＋区切り＋発話の 1 段落）へ DOM ごと組み替える**。
        # 容器のクラスを talk-style-inline へ差し替えるので、以降は inline 用 CSS が
        # そのまま効き、Kindle 専用 CSS をほとんど持たずに済む。
        #
        # name=off が指定されていても Kindle では話者名を見せる（talk-name-off クラスを外す）。
        # アバターも左右振り分けも吹き出しも無い Kindle で名前まで落とすと、話者を判別する
        # 手がかりが皆無になるため。前処理は name=off でも .talk-name を DOM に残している。
        #
        # クリーン EPUB・PDF には適用しない（Kindle 専用フェーズからのみ呼ばれる）。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)

            changed = doc.css('div.talk').map { flatten_talk_container!(doc, it) }.any?
            next unless changed

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} の会話文を Kindle 表示へ変換しました")
          end
          html_files
        end

        # 会話文コンテナ 1 つを inline 形式へ組み替える。
        # 区切り文字は前処理が付けた data-talk-sep から取る（talk.yml を読み直さない）。
        def flatten_talk_container!(doc, container)
          separator = container['data-talk-sep'].to_s
          separator = '：' if separator.empty?
          changed = container.css('.talk-item').map { flatten_talk_item!(doc, it, separator) }.any?

          classes = container['class'].to_s.split
          if classes.delete('talk-style-chat')
            classes << 'talk-style-inline' unless classes.include?('talk-style-inline')
            container['class'] = classes.join(' ')
            changed = true
          end
          container.remove_attribute('data-talk-sep')
          changed
        end

        # 発話 1 つを「名前＋区切り＋発話」の 1 段落へ。既に inline の原稿は移動不要で、
        # 隠しクラスの除去と左右クラスの掃除だけを行う。
        def flatten_talk_item!(doc, item, separator)
          changed = item.css('img.talk-icon').map { it.remove }.any?
          changed |= strip_talk_side_classes!(item)

          name = item.at_css('.talk-name')
          return changed if name.nil?

          # name=off でも Kindle では見せる（隠しクラスを外す）
          changed |= remove_css_class!(name, 'talk-name-off')
          item.css('.talk-sep').each { changed |= remove_css_class!(it, 'talk-name-off') }

          target = item.at_css('.talk-body p') || item.at_css('p')
          if target && !name.ancestors.include?(target)
            sep_node = Nokogiri::XML::Node.new('span', doc)
            sep_node['class'] = 'talk-sep'
            sep_node.content = separator
            # prepend は先頭挿入なので「区切り → 名前」の順に入れると [名前, 区切り, 本文] になる
            target.prepend_child(sep_node)
            target.prepend_child(name)
            changed = true
          end

          item.css('.talk-speaker').each do |speaker|
            speaker.remove
            changed = true
          end
          changed
        end

        # 左右振り分けクラスを外す（inline では左右に振らない）。
        def strip_talk_side_classes!(item)
          classes = item['class'].to_s.split
          remaining = classes.reject { %w[talk-left talk-right].include?(it) }
          return false if remaining.size == classes.size

          item['class'] = remaining.join(' ')
          true
        end

        # 要素から class を 1 つ取り除く（取り除いたら true）。
        def remove_css_class!(node, klass)
          classes = node['class'].to_s.split
          return false unless classes.delete(klass)

          node['class'] = classes.join(' ')
          true
        end
      end
    end
  end
end
