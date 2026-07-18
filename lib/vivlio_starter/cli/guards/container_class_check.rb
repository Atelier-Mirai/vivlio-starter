# frozen_string_literal: true

require 'did_you_mean'
require_relative 'container_scanner'

module VivlioStarter
  module CLI
    module Guards
      # contents/*.md の `:::{.class}` に未知のクラス名が使われていないかを検出して警告する。
      #
      # なぜ黙殺されるのか:
      #   `:::{.class}` の div 化には二経路ある。Ruby 前処理（convert_container_blocks）が扱う
      #   のは 6 クラスのみで、残りはすべて組み込み置換ルール（ReplacementRules）の汎用正規表現が
      #   `<div class="$1">` へ置換する。後者はクラス名を一切知らないため、`:::{.notion}` は
      #   無言で `<div class="notion">` になり、CSS が当たらないまま素の段落として組まれる。
      #   著者は完成 PDF を目視するまで気づけない。
      #
      # なぜ警告（停止しない）なのか:
      #   「CSS を書く前に原稿を先に書く」という順序を妨げないため。
      #
      # 許可リスト: stylesheets/**/*.css のクラスセレクタを自動抽出する。custom.css が
      #   著者の自由記述用に用意されているため「クラスに CSS を書けば自動的に許可される」で
      #   完結する。過剰許可（Prism のトークンクラス等が混ざる）は偽陰性しか生まないため許容する。
      class ContainerClassCheck < BaseCheck
        # 経路 A（Ruby 前処理）が扱うクラス。convert_container_blocks の 6 クラスに加え、
        # showcase は ShowcaseTransformer がブロックごと消費して figure.vs-showcase へ
        # 変換するため、CSS に `.showcase` セレクタが存在しないのが正しい状態。
        # 他は CSS にも存在するが、CSS 側が消えても検証が壊れないよう明示しておく。
        PREPROCESSED_CLASSES = %w[
          book-card rotate-table long-table text-right text-center text-left showcase
        ].freeze

        # CSS のクラスセレクタ。小数（`0.5em`）や `nth-child()` を拾わないよう直前を除外する。
        CSS_CLASS_SELECTOR = /(?<![\w.\-])\.([a-zA-Z_][\w-]*)/

        # 提示する修正候補の上限。実データでは 1 件に収まるが、似た名前のクラスが
        # 増えたときに候補が並びすぎないよう蓋をする。
        MAX_SUGGESTIONS = 3

        # @param allowed_classes [Array<String>, nil] 追加で許可するクラス（既定は book.yml から読む）
        def initialize(allowed_classes: nil)
          super()
          @extra_classes = allowed_classes || configured_allowed_classes
        end

        # @return [Array<Violation>] 警告の配列（合格なら空配列）
        def validate
          markdown_files.flat_map { check_file(it) }
        end

        private

        def markdown_files = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).sort

        def check_file(path)
          ContainerScanner.scan(path).select { it.kind == :open }.flat_map do |directive|
            directive.classes
                     .reject { known_classes.include?(it) }
                     .map { unknown_class_warning(path, directive, it) }
          end
        end

        # 行番号を持つ警告は `path:line - 内容` の形にする（LinkImageValidator と同形。
        # 端末でクリックして該当行へ飛べる）。
        def unknown_class_warning(path, directive, klass)
          warning(
            "#{path}:#{directive.line_number} - 未知のコンテナクラス '.#{klass}' を検出しました",
            detail: warning_detail(directive, klass)
          )
        end

        # 現状・候補・対処方法を行配列で返す（warning-messages-actionable 方針）。
        def warning_detail(directive, klass)
          detail = ["現状: #{opener_for(directive.classes)}"]
          candidates = suggest(klass)
          detail << "候補: #{candidate_openers(directive, klass, candidates).join(', ')}" unless candidates.empty?
          detail << '→ CSS が当たらないため、枠が付かず素の段落として組まれます'
          detail << '→ 意図したクラスであれば stylesheets/custom.css に定義を追加するか、'
          detail << '  config/book.yml の preflight.allowed_classes に追加してください'
          detail
        end

        # 誤りのクラスだけを候補で差し替えた開始行を、候補ごとに組み立てる。
        # 複数クラス（`:::{.notice .colunm}`）でもそのまま貼り替えられる形で示す。
        def candidate_openers(directive, klass, candidates)
          candidates.map do |candidate|
            opener_for(directive.classes.map { |cls| cls == klass ? candidate : cls })
          end
        end

        def opener_for(classes) = ":::{#{classes.map { ".#{it}" }.join(' ')}}"

        # DidYouMean::SpellChecker#correct は Jaro-Winkler 類似度の降順に並び、
        # さらにレーベンシュタイン距離（語長 × 0.25 が上限）で足切り済み。
        # 独自の並べ替えを重ねても順序は変わらないため、stdlib の結果をそのまま使う。
        def suggest(klass)
          DidYouMean::SpellChecker.new(dictionary: known_classes).correct(klass).first(MAX_SUGGESTIONS)
        end

        # CSS 抽出は I/O を伴うため、ガード 1 回の実行につき一度だけ構築する。
        # sort するのは、SpellChecker の sort_by! が安定ソートではなく、Dir.glob 由来の
        # 辞書順が環境依存だと Jaro-Winkler 同点時の候補順がぶれるため。
        def known_classes
          @known_classes ||= (css_classes + PREPROCESSED_CLASSES + @extra_classes).uniq.sort.freeze
        end

        def css_classes
          Dir.glob(File.join(Common.stylesheets_dir, '**', '*.css')).flat_map do |path|
            strip_css_noise(File.read(path, encoding: 'utf-8')).scan(CSS_CLASS_SELECTOR).flatten
          end
        end

        # コメントと文字列リテラルを除去する。`content: ".foo"` を
        # クラスセレクタとして誤って拾わないため。
        def strip_css_noise(css) = css.gsub(%r{/\*.*?\*/}m, ' ').gsub(/"[^"]*"|'[^']*'/, ' ')

        def configured_allowed_classes
          Array(Common::CONFIG&.dig(:preflight, :allowed_classes)).map(&:to_s)
        end
      end
    end
  end
end
