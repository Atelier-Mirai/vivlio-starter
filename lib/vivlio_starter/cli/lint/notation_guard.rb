# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/notation_guard.rb
# ================================================================
# 責務:
#   VFM 記法（機械データ）を中和したテキストを返す。vs lint（textlint・
#   スペルチェック）が記法を日本語の文として読んでしまう誤検出を、
#   設定ファイルではなく lint システムの内部で断つ。
#
# なぜ設定ファイルではないのか:
#   従来は config/textlint_allowlist.yml の「VFM 記法」エントリ（正規表現）で
#   抑え込んでいたが、allowlist は本来「この語は正しい日本語として扱え」という
#   語彙辞書であり、記法は語彙ではない。しかも allowlist はマッチした文字列を
#   消すだけで「この行はブロックの中だ」という文脈を持てないため、ブロック全体を
#   1 文と数える sentence-length の誤検出は原理的に消せなかった。記法を知って
#   いるのは lint システム自身なのだから、システム内部でガードする。
#
# なぜ Masking と別モジュールなのか:
#   Masking.each_prose_line は前処理・索引・メトリクスなど 10 箇所以上から
#   「コード領域解釈の唯一の実装」として使われている。記法の知識をそこへ混ぜると
#   lint と無関係な前処理まで意味が変わる（例: showcase ブロック内の画像行を
#   ImagePathNormalizer が見なくなる）。記法の中和は lint 系だけの要求なので、
#   知識はこのモジュールへ集約し、Masking はコード領域の解釈に徹させる。
#
# 不変条件:
#   I1 行数を必ず保存する（指摘の行番号表示がずれると実用に耐えないため）
#   I3 地の文は 1 文字も落とさない（ふりがなの親文字は地の文なので残す）
#   -- コード領域には触れない（textlint はコード前後のスペース等、コードの
#      存在自体を検査する。消すと検査に穴が開く）
#   -- 文書構造を変えない: HTML コメントの開閉 `<!--`/`-->` を巻き込んで消さない。
#      判定に迷う行はガードしない（素のまま渡す＝ガード導入前と同じ扱いが常に安全側）
#
# 仕様: docs/specs/lint-notation-guard-spec.md §3
# ================================================================

require 'set'
require_relative '../masking'

module VivlioStarter
  module CLI
    module Lint
      # VFM 記法の中和（lint 系専用）。
      module NotationGuard
        module_function

        # 機械データ（座標・オプション）を本文として持つコンテナ名。
        # 記法を追加するときはここへ 1 語加えればガードが追従する。
        MACHINE_DATA_CONTAINERS = %w[showcase].freeze

        # 機械データ・ブロックの開始行（例: `:::{.showcase}`）。
        # ShowcaseTransformer::BLOCK_PATTERN の開始側と揃える（行末に本文が続く
        # `:::{.showcase} foo` は同 PATTERN が消費しない＝ブロックではないため、
        # ガードもブロックとして扱わない）。
        MACHINE_BLOCK_OPEN =
          /\A:::\s*\{\s*\.(?:#{Regexp.union(MACHINE_DATA_CONTAINERS).source})\s*\}[ \t]*\r?\n?\z/

        # 機械データ・ブロックの終了行（例: `:::`）。
        MACHINE_BLOCK_CLOSE = /\A:::[ \t]*\r?\n?\z/

        # コンテナのマーカー行（開始・終了とも）。コロン 3 つ以上＋任意の属性ブレースで
        # **行全体が構成される**ものだけをマーカーとみなす。
        #
        # 「:::" で始まる行」まで広げてはならない: コメントアウトされたコンテナの閉じ
        # `:::-->` を空行化すると HTML コメントの `-->` が消え、コメントが永久に閉じず、
        # その中身（表・数式）を読んだ textlint が暴走する実害があった（94 章で CPU 99%）。
        # マーカーでないものはガードの対象外＝素のまま textlint へ渡す（現状維持が正しい）。
        CONTAINER_MARKER = /\A[ \t]*:{3,}[ \t]*(?:\{[^{}\n]*\})?[ \t]*\r?\n?\z/

        # ふりがな記法 `{親文字|ふりがな}`。
        FURIGANA = /\{([^{}|]*)\|[^{}]*\}/

        # クラス属性記法 `{.classname}`。
        CLASS_ATTRIBUTE = /\{\.[-\w]+\}/

        # 記法を中和したテキストを返す。行数は入力と必ず一致する（I1）。
        # @param text [String] 原稿の内容
        # @return [String] 記法を中和した内容
        def strip_notation(text)
          prose   = prose_lines(text)
          machine = machine_block_lines(text, prose)

          text.each_line.with_index(1).map do |line, lineno|
            if !prose.include?(lineno)          then line          # コード領域は不変
            elsif machine.include?(lineno)      then blank(line)   # G1 機械データ・ブロック
            elsif line.match?(CONTAINER_MARKER) then blank(line)   # G2 コンテナのマーカー行
            else neutralize_inline(line)                           # G3 ふりがな → G4 クラス属性
            end
          end.join
        end

        # コード領域でない（＝地の文の）行番号の集合。判定は Masking へ委ねる。
        def prose_lines(text)
          prose = Set.new
          Masking.each_prose_line(text) { |_line, lineno| prose << lineno }
          prose
        end
        private_class_method :prose_lines

        # 機械データ・ブロックに属する行番号の集合（開始行・内容行・終了行を含む）。
        #
        # 終了行が無いままファイル末尾に達したブロックは「無かったもの」として扱う。
        # ShowcaseTransformer::BLOCK_PATTERN は閉じが無ければ一致せず、その中身は
        # 原稿にそのまま残って本文として組まれる。ガードだけが先に消すと、実在する
        # 文が textlint の目から消えて検査に穴が開く（未終了フェンスを退避しない
        # Masking の方針とも揃う）。
        def machine_block_lines(text, prose)
          lines   = Set.new
          pending = nil

          text.each_line.with_index(1) do |line, lineno|
            next unless prose.include?(lineno)

            if pending.nil?
              pending = [lineno] if line.match?(MACHINE_BLOCK_OPEN)
            else
              pending << lineno
              if line.match?(MACHINE_BLOCK_CLOSE)
                lines.merge(pending)
                pending = nil
              end
            end
          end

          lines
        end
        private_class_method :machine_block_lines

        # 行内の記法を中和する（G3 → G4）。
        # 地の文が記法を「解説している」インラインコード（例: `{.aki}` の書き方を
        # 説明する行）を壊さないよう、コードを退避してから置換する。
        def neutralize_inline(line)
          protected_line, spans = Masking.protect_code(line)
          neutralized = protected_line
                        .gsub(FURIGANA) { ::Regexp.last_match(1) } # 親文字は地の文なので残す（I3）
                        .gsub(CLASS_ATTRIBUTE, '')
          Masking.restore_code(neutralized, spans)
        end
        private_class_method :neutralize_inline

        # 行の中身を落として改行だけ残す（行数保存 = I1）。
        # 末尾に改行が無い最終行は空文字になり、行数も末尾の形状も変わらない。
        def blank(line) = line.end_with?("\n") ? "\n" : ''
        private_class_method :blank
      end
    end
  end
end
