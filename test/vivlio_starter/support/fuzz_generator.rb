# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/support/fuzz_generator.rb
#
# ファズ / プロパティテスト用の決定的な入力ジェネレータ
# docs/specs/test-suite-expansion-spec.md §7.3
#
# 【方針】
#   - 専用 gem は使わない（依存追加を避ける）
#   - シード固定で決定的に生成する（CI / 再現性のため）
#   - 入力は (a) 境界値 (b) ランダム文字列 (c) 妥当入力のランダム変異 の 3 系統
# =============================================================================

module VsTestSupport
  module FuzzGenerator
    module_function

    # YAML / 設定ファイルを壊しやすい文字を多めに含む文字プール
    CHAR_POOL = [
      "a", "z", "0", "9", "_", "-", ".", "/",
      '"', "'", ":", "#", "\\", "[", "]", "{", "}", "|", "&", "*", ">",
      " ", "\t", "\n", "\r\n", "　",
      "あ", "漢", "ガ", "🌸", " ", "​"
    ].freeze

    # 入力破壊に使う挿入文字（引用符・括弧・制御文字・マルチバイト）
    MUTATION_CHARS = ['"', "'", "[", "{", "\\", "#", "\x00", "あ", "🌸", "\n"].freeze

    # パーサ実装が落ちやすい境界値（不正 UTF-8 バイト列を含む）
    def boundary_inputs
      [
        "",
        " ",
        "\n\n\n",
        "﻿key: value\n",                      # BOM 付き
        "key: value\r\nkey2: value2\r\n",          # CRLF
        "a" * 50_000,                              # 巨大単一行
        ("x: 1\n" * 5_000),                        # 巨大複数行
        "\x00\x01\x02\x03",                        # 制御文字
        (+"\xFF\xFE\xC3").force_encoding("UTF-8"), # 不正 UTF-8 バイト列
        (+"book:\n  main_title: \"\xE3\x81break\"\n").force_encoding("UTF-8"), # 途中で壊れたマルチバイト
        "---\n--- \n---\n",                        # YAML ドキュメント区切り
        "&anchor *alias\n",                        # アンカー / エイリアス
        "!!ruby/object {}\n",                      # 危険タグ
        "{{MAIN_TITLE}}",                          # プレースホルダ残骸
        "%YAML 1.2\n%TAG ! !\n"                    # ディレクティブ
      ]
    end

    # ランダム文字列 count 件 + base_samples の変異を加えた決定的コーパスを返す
    # @param seed [Integer] 乱数シード（固定して再現性を保証する）
    # @param count [Integer] ランダム文字列の件数
    # @param base_samples [Array<String>] 変異元になる妥当入力
    # @return [Array<String>]
    def corpus(seed:, count: 100, base_samples: [])
      rng = Random.new(seed)
      randoms = Array.new(count) { random_string(rng) }
      mutated = base_samples.flat_map { |sample| Array.new(5) { mutate(sample, rng) } }
      boundary_inputs + randoms + mutated
    end

    def random_string(rng)
      Array.new(rng.rand(0..120)) { CHAR_POOL[rng.rand(CHAR_POOL.size)] }.join
    end

    # 妥当入力へ 1〜3 箇所のランダム破壊（挿入・削除・置換）を加える
    def mutate(source, rng)
      chars = source.chars
      rng.rand(1..3).times do
        case rng.rand(3)
        when 0
          chars.insert(rng.rand(chars.size + 1), MUTATION_CHARS[rng.rand(MUTATION_CHARS.size)])
        when 1
          chars.delete_at(rng.rand(chars.size)) unless chars.empty?
        when 2
          chars[rng.rand(chars.size)] = MUTATION_CHARS[rng.rand(MUTATION_CHARS.size)] unless chars.empty?
        end
      end
      chars.join
    end
  end
end
