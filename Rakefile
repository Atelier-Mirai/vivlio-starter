# frozen_string_literal: true

require 'rake/testtask'

# ==================================================================
# 拡張：rake -T の出力を、安全かつ確実に指定の順序で表示する
# ==================================================================
class << Rake.application
  def display_tasks_and_comments
    # コメントが設定されているタスクのみを抽出
    displayable_tasks = tasks.select { |t| t.comment }

    # 引数による絞り込み（rake -T pattern）が指定されている場合は安全に考慮
    if options.respond_to?(:show_task_pattern) && options.show_task_pattern
      displayable_tasks = displayable_tasks.select { |t| t.name =~ options.show_task_pattern }
    end

    # 【重要】出力させたい理想の順番を明示的に指定
    custom_order = ['test', 'test:standard', 'test:versions', 'test:layout', 'test:targets', 'test:type3', 'test:kindle', 'test:manual', 'test:package', 'test:release', 'test:canary', 'reinstall']
    displayable_tasks = displayable_tasks.sort_by { |t| custom_order.index(t.name) || 999 }

    # 表示幅を計算して綺麗にフォーマット出力
    width = displayable_tasks.map { |t| t.name.length }.max || 10
    displayable_tasks.each do |t|
      printf "rake %-#{width}s  # %s\n", t.name, t.comment
    end
  end
end

# ------------------------------------------------------------------
# 通常テストタスク
# ------------------------------------------------------------------
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude(
    "test/**/page_layout/**/*_test.rb",
    "test/**/release/**/*_test.rb",
    "test/**/targets/**/*_test.rb",
    "test/**/kindle/**/*_test.rb",
    "test/**/type3/**/*_test.rb"
  )
  t.warning = false
end

# 既存の "Run tests" を完全にクリアしてから上書き
Rake::Task["test"].clear_comments
Rake::Task["test"].comment = "通常テストスイーツを実行"

# ------------------------------------------------------------------
# Standard モード強制テスト（VIVLIO_PDF_PLUGIN=disable）
# ------------------------------------------------------------------
# 開発機には拡張プラグイン（vivlio-starter-pdf）が入っているため、通常の `rake test` は
# 常に EnhancedProvider 経路を通り、MIT 本体の StandardProvider 経路は exercise されない
# （プロバイダ選択テストやノンブル等は enhanced 側だけが走る）。プラグインを uninstall
# せずとも、本体が備える `VIVLIO_PDF_PLUGIN=disable` で StandardProvider を強制し、
# 同じスイートを standard 経路で実行して「standard 版の破損」を検知する。
# 環境変数を汚さないよう独立プロセスで実行する。
namespace :test do
  task :standard do
    sh({ 'VIVLIO_PDF_PLUGIN' => 'disable' }, 'bundle exec rake test')
  end
end

Rake::Task["test:standard"].comment =
  "Standard モード強制テスト（VIVLIO_PDF_PLUGIN=disable で MIT 本体経路を検証・プラグイン uninstall 不要）"

# ------------------------------------------------------------------
# 対応 Ruby 版でのテスト
# ------------------------------------------------------------------
# gemspec が Ruby 3.4 以上を謳う以上、それが本当かは実際に走らせないと分からない。
# `it`（暗黙ブロック引数）は 3.3 以下でも構文エラーにならず「it というメソッドの
# 呼び出し」として通り、実行時に NameError になる——静的解析では捕まらない。
#
# 通常の `rake test` には含めない。本スイートは 1 版で約 70 秒あり、書きながら回す
# ループを倍にする価値は無い（両版で結果が割れるのは新しい構文・API を採り入れた
# ときだけである）。push 前とリリース前に叩く想定。
# CI（GitHub Actions）は版をマトリクスで分担するため、そちらでは各ジョブが 1 回走る。
SUPPORTED_RUBY_VERSIONS = %w[3.4.10 4.0.6].freeze

# 別の Ruby を子プロセスで起動する以上、親の bundler 環境は必ず捨てる。
# `bundle exec rake test:versions` から呼ばれると、親（現在の Ruby）の bundler を
# 子（別の Ruby）が読みに行き、テストが始まる前に LoadError で落ちる。
# nil を渡すと、その環境変数は子から取り除かれる。
UNBUNDLED_ENV = {
  'RUBYOPT' => nil, 'RUBYLIB' => nil, 'GEM_HOME' => nil, 'GEM_PATH' => nil,
  'BUNDLE_GEMFILE' => nil, 'BUNDLE_BIN_PATH' => nil, 'BUNDLER_VERSION' => nil,
  'BUNDLER_SETUP' => nil
}.freeze

namespace :test do
  task :versions do
    missing = SUPPORTED_RUBY_VERSIONS - `rbenv versions --bare`.split("\n")
    unless missing.empty?
      abort <<~MESSAGE
        次の Ruby が rbenv に入っていません: #{missing.join(', ')}
          #{missing.map { "rbenv install #{it}" }.join("\n  ")}
      MESSAGE
    end

    # 版ごとに bundle が要る。未導入なら黙って入れる（その版の初回は数分かかる）
    failed = SUPPORTED_RUBY_VERSIONS.reject do |version|
      puts "\n=== Ruby #{version} ==="
      env = UNBUNDLED_ENV.merge('RBENV_VERSION' => version)

      unless system(env, 'rbenv exec bundle check', out: File::NULL, err: File::NULL)
        next false unless system(env, 'rbenv exec bundle install --quiet')
      end

      system(env, 'rbenv exec bundle exec rake test')
    end

    abort "\n失敗した Ruby: #{failed.join(', ')}" unless failed.empty?
    puts "\n全 Ruby 版で通過: #{SUPPORTED_RUBY_VERSIONS.join(' / ')}"
  end
end

Rake::Task["test:versions"].comment =
  "対応する全 Ruby 版（#{SUPPORTED_RUBY_VERSIONS.join(' / ')}）で通常テストを実行"

# ------------------------------------------------------------------
# 判型確認用専用テスト
# ------------------------------------------------------------------
namespace :test do
  Rake::TestTask.new(:layout) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/page_layout/**/*_test.rb"
    t.warning = false
  end
end

# 既存の "Run tests for layout" を完全にクリアしてから上書き
Rake::Task["test:layout"].clear_comments
Rake::Task["test:layout"].comment = "判型テスト（vs build を実際に実行する統合テスト）"

# ------------------------------------------------------------------
# ターゲット整合性テスト（単体/複合 targets の実ビルド突き合わせ）
# 実ビルドを 7 通り回すため最も遅い。通常テストからは除外
# ------------------------------------------------------------------
namespace :test do
  Rake::TestTask.new(:targets) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/targets/**/*_test.rb"
    t.warning = false
  end
end

Rake::Task["test:targets"].clear_comments
Rake::Task["test:targets"].comment = "ターゲット整合性テスト（pdf/print_pdf/epub を単体・複合でビルドし突き合わせ）"

# ------------------------------------------------------------------
# Techbook モードの Type 3 フォント検証（techbook true/false の実ビルド比較）
# 全章ビルドを 2 回回すため 10 分以上かかる。通常テストからは除外
# ------------------------------------------------------------------
namespace :test do
  Rake::TestTask.new(:type3) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/type3/**/*_test.rb"
    t.warning = false
  end
end

Rake::Task["test:type3"].clear_comments
Rake::Task["test:type3"].comment = "Type 3 フォント検証（techbook: true/false を実ビルドし混入量を比較）"

# ------------------------------------------------------------------
# Kindle 変換検証テスト（opt-in・Mac/Win ローカル専用）
# Kindle Previewer 3 CLI（kindlepreviewer）で EPUB を実変換し、
# conversionLog の画像系警告（W14015/W14012/W14010）ゼロを検証する。
# CLI 未導入環境では skip するため、Linux CI でも安全。実ビルドを伴い遅いので
# 通常 test からは除外する。
# ------------------------------------------------------------------
namespace :test do
  Rake::TestTask.new(:kindle) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/kindle/**/*_test.rb"
    t.warning = false
  end
end

Rake::Task["test:kindle"].clear_comments
Rake::Task["test:kindle"].comment = "Kindle 変換検証（kindlepreviewer で実変換し画像系警告ゼロを確認・要 Kindle Previewer 3）"

# ------------------------------------------------------------------
# RC 品質保証テスト群（docs/specs/test-suite-expansion-spec.md §3）
# 実ビルドを伴うため通常テストからは除外されている
# ------------------------------------------------------------------
namespace :test do
  # マニュアル実体の実ビルドと成果物検査（MB / FT / EP / ID）
  Rake::TestTask.new(:manual) do |t|
    t.libs << "test"
    t.test_files = FileList["test/vivlio_starter/release/**/*_test.rb"].exclude(
      "test/**/packaging_test.rb",
      "test/**/canary_test.rb"
    )
    t.warning = false
  end

  # gem ビルド → 隔離インストール → 動作確認（PK）
  Rake::TestTask.new(:package) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/release/packaging_test.rb"
    t.warning = false
  end

  # 上流（@vivliostyle/cli 最新版）での破壊検知（CN）。リリース判定には含めない
  Rake::TestTask.new(:canary) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/release/canary_test.rb"
    t.warning = false
  end

  # RC 前総点検（canary は上流要因のため含めない）
  # test（Enhanced）に加え test:standard（Standard 強制）も回し、両プロバイダ経路を保証する。
  task release: ['test', 'test:standard', 'test:layout', 'test:targets', 'test:manual', 'test:package']
end

Rake::Task["test:manual"].clear_comments
Rake::Task["test:manual"].comment = "マニュアル実ビルド + 成果物検査（警告ゼロ / フォント / EPUB / 冪等性）"
Rake::Task["test:package"].clear_comments
Rake::Task["test:package"].comment = "パッケージング E2E（gem build → 隔離インストール → ビルド確認）"
Rake::Task["test:canary"].clear_comments
Rake::Task["test:canary"].comment = "依存カナリア（@vivliostyle/cli 最新版での破壊検知）"
Rake::Task["test:release"].comment = "RC 前総点検（test → standard → layout → targets → manual → package を一括実行）"

# デフォルトタスク（rake -T には出さない）
task default: :test

# ------------------------------------------------------------------
# gem のアンインストール → ビルド → インストールを一括実行
# ------------------------------------------------------------------
desc "gem のアンインストール → ビルド → インストールを一括実行"
task :reinstall do
  gemspec = Dir['*.gemspec'].first
  raise 'gemspec が見つかりません' unless gemspec

  require_relative 'lib/vivlio_starter/version'
  version = VivlioStarter::VERSION
  gem_name = 'vivlio-starter'

  sh "gem uninstall #{gem_name} --version #{version} --executables --ignore-dependencies 2>/dev/null || true"
  sh "gem build #{gemspec}"

  gem_file = Dir["#{gem_name}-*.gem"].max_by { |f| File.mtime(f) }
  raise "ビルドされた gem ファイルが見つかりません" unless gem_file

  sh "gem install #{gem_file}"
end

# 数式表示の実機確認（Kindle Previewer / PDF）を回すための足回り。
# 検査ページの正本は test/vivlio_starter/fixtures/math/math-check.md で、
# contents/ 側は使い捨ての複製。手でコピーして回すと**正本の更新を取りこぼす**ので、
# 毎回ここから置き直す。
namespace :math do
  MATH_CHECK_SOURCE = 'test/vivlio_starter/fixtures/math/math-check.md'
  MATH_CHECK_TARGET = 'contents/81-math-check.md'

  desc '数式チェックページを contents/ へ置き、リポジトリ版の vs でビルドする（rake reinstall 不要）'
  task :check do
    require 'fileutils'
    abort "🔴 検査ページが見つかりません: #{MATH_CHECK_SOURCE}" unless File.exist?(MATH_CHECK_SOURCE)

    FileUtils.cp(MATH_CHECK_SOURCE, MATH_CHECK_TARGET)
    puts "COPY  #{MATH_CHECK_SOURCE} -> #{MATH_CHECK_TARGET}"

    # 段取りの取りこぼしを先に知らせる（ビルドしてから気づくと時間を捨てる）
    catalog = File.read('config/catalog.yml')
    unless catalog.match?(/^\s*-\s*81-math-check/)
      puts '🟡 config/catalog.yml に 81-math-check が見当たりません（章が組まれない可能性があります）'
    end
    targets = File.read('config/book.yml')[/^\s*targets:\s*(.+)$/, 1].to_s
    puts "🟡 config/book.yml の targets が「#{targets.strip}」です（Kindle を見るなら kindle を含めてください）" unless targets.include?('kindle')

    # **リポジトリの bin/vs を直接叩く**ので `rake reinstall` が要らない。
    # PATH 上の `vs` は導入済み gem を使うため、変更が反映されないまま検証してしまう。
    sh "#{RbConfig.ruby} -Ilib bin/vs build"
  end

  desc '数式チェックページの複製を contents/ から取り除く'
  task 'check:clean' do
    require 'fileutils'
    FileUtils.rm_f(MATH_CHECK_TARGET)
    puts "REMOVE #{MATH_CHECK_TARGET}"
  end
end

namespace :mazegaki do
  desc '交ぜ書き辞書の第 2 層（lint/data/mazegaki.tsv）を元データから作り直す'
  task :build do
    # 本書の原稿へ当てた実測値も一緒に出る。条件を変えたら誤検出が増えていないか見ること。
    ruby '-Ilib lib/vivlio_starter/cli/lint/data/filter.rb'
  end
end
