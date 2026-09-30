# frozen_string_literal: true

# ================================================================
# scripts/index_candidate_eval.rb — vs index:auto の候補の質を測る
# ================================================================
# 著者が選んだ索引語（config/index_glossary_terms.yml の [i] の語）を正解とみなし、
# 候補の順位付けがそれをどれだけ当てるかを測る。候補の拾い方や重み
# （IndexCandidateExtractor・ScoringEngine）を変えたら、前後でこれを回して比べる。
# 改善案 #98 で、変更を 1 つずつ入れて測るのに使った。
#
# 測るもの:
#   再現率  … 上位 N 位（既定は目安の 206 位・300 位・400 位）までに入った正解の割合
#   ノイズ  … 目安の語数までに入った、正解でない語の数
#   取りこぼし … 候補にならなかった正解と、目安より下に並んだ正解
#
# 候補は辞書を空とみなして並べる（登録語と同じ土俵にはしない）。候補の拾い方
# そのものの質を見るためで、`vs index:plan` の推奨候補の件数とは一致しない。
#
# 正解は 1 冊ぶんの選定なので、数字を上げることだけを目標にしない。重みを振って
# 頂点を探すときは、1 冊に合わせすぎないよう伸びが平らになり始める値を採る
# （#98 の見出しの加点は 60 点が頂点、採ったのは 45 点）。
#
# 使い方:
#   ruby scripts/index_candidate_eval.rb                    # 要約
#   ruby scripts/index_candidate_eval.rb --detail           # ノイズの語と性質も出す
#   ruby scripts/index_candidate_eval.rb --target 180       # 目安の語数を変える
#   ruby scripts/index_candidate_eval.rb --weight heading=60 # 性質の重みを差し替えて測る
# ================================================================

require 'optparse'
require 'set'
require 'yaml'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'lib'))
Dir.chdir(ROOT)

options = { target: 206, detail: false, weights: {} }
OptionParser.new do |opts|
  opts.banner = 'Usage: ruby scripts/index_candidate_eval.rb [--detail] [--target N] [--weight trait=value]'
  opts.on('--detail', 'ノイズの語と性質も出す') { options[:detail] = true }
  opts.on('--target N', Integer, '目安の語数（既定 206）') { options[:target] = it }
  opts.on('--weight TRAIT=VALUE', '性質の重みを差し替える（例: heading=60）') do |pair|
    trait, value = pair.split('=', 2)
    options[:weights][trait.to_sym] = Float(value)
  end
end.parse!

require 'vivlio_starter/cli/loader'

module IndexCandidateEval
  CLI = VivlioStarter::CLI
  TRAIT_MARKS = { definition: 'd', technical: 't', noun_sequence: 'n', heading: 'h' }.freeze

  module_function

  def run(target:, detail:, weights:)
    override_weights(weights)
    gold = gold_terms
    extractor = extract
    ranked = extractor.term_scores.sort_by { |term, score| [-score, term] }.map(&:first)
    rank_of = ranked.each_with_index.to_h { |term, i| [term, i + 1] }

    report(ranked, rank_of, gold, target)
    report_noise(ranked.first(target) - gold.to_a, extractor) if detail
  end

  # 正解: 辞書の索引語（索引のみ・両方）
  def gold_terms
    YAML.load_file('config/index_glossary_terms.yml')['terms']
        .select { it['flags'].to_s.include?('i') }.to_set { it['term'] }
  end

  # 候補を抽出する（進捗の表示は捨てる）
  def extract
    chapters = CLI::IndexCommands.resolve_chapters([])
    extractor = CLI::IndexCommands::IndexCandidateExtractor.new
    quietly { extractor.extract_from_chapters!(chapters) }
    extractor
  end

  def report(ranked, rank_of, gold, target)
    ranks = gold.filter_map { rank_of[it] }.sort
    within = ->(limit) { ranks.count { it <= limit } }
    percent = ->(count) { format('%.1f%%', 100.0 * count / gold.size) }

    puts "候補 #{ranked.size} 件 / 正解 #{gold.size} 語"
    [target, 300, 400].uniq.each { puts "  #{it} 位までの再現率: #{percent.(within.(it))}（#{within.(it)} 語）" }
    puts "  #{target} 位までのノイズ: #{target - within.(target)} 語"
    puts "  正解の順位の中央値: #{ranks[ranks.size / 2]}（候補になった正解 #{ranks.size} 語）"

    missing = gold.reject { rank_of[it] }
    below = gold.select { rank_of[it] && rank_of[it] > target }.sort_by { rank_of[it] }
    puts "候補にならなかった正解（#{missing.size}）: #{missing.to_a.join(' ')}"
    puts "#{target} 位より下の正解（#{below.size}）: #{below.first(40).map { "#{it}(#{rank_of[it]})" }.join(' ')}"
  end

  # ノイズの語を、拾った経路の印（d 定義文・t 専門用語・n 名詞連続・h 見出し）つきで並べる
  def report_noise(noise, extractor)
    puts "\n#{noise.size} 語のノイズ:"
    noise.each_slice(10) do |slice|
      marks = slice.map { |term| "#{term}[#{extractor.scoring.breakdown(term)[:traits].map { TRAIT_MARKS[it] }.join}]" }
      puts "  #{marks.join(' ')}"
    end
  end

  def override_weights(weights)
    return if weights.empty?

    engine = CLI::IndexCommands::ScoringEngine
    unknown = weights.keys - engine::TRAIT_WEIGHTS.keys
    abort "未知の性質: #{unknown.join(', ')}（#{engine::TRAIT_WEIGHTS.keys.join(' / ')}）" if unknown.any?

    merged = engine::TRAIT_WEIGHTS.merge(weights).freeze
    engine.send(:remove_const, :TRAIT_WEIGHTS)
    engine.const_set(:TRAIT_WEIGHTS, merged)
  end

  def quietly
    original = $stdout
    $stdout = File.open(File::NULL, 'w')
    yield
  ensure
    $stdout = original
  end
end

IndexCandidateEval.run(**options)
