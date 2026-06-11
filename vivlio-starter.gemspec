# frozen_string_literal: true

require_relative 'lib/vivlio_starter/version'

Gem::Specification.new do |spec|
  spec.name          = 'vivlio-starter'
  spec.version       = VivlioStarter::VERSION
  spec.authors       = ['Atelier Mirai']
  spec.email         = ['contact@atelier-mirai.net']

  spec.summary       = 'Markdown で書いた原稿から高品質な PDF・EPUB を生成する書籍制作 CLI'
  spec.description   = 'CSS 組版エンジン Vivliostyle をコアに据え、前処理（QueryStream 展開・画像最適化・クロスリファレンス）からビルド、後処理（PDF しおり・表紙結合・圧縮）まで、執筆から入稿に至る工程を自動化する CLI ツールです。'
  spec.homepage      = 'https://github.com/Atelier-Mirai/vivlio-starter'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 4.0'

  # 同梱物はホワイトリスト方式で最小限に絞る。
  # 実行コードは bin/ と lib/ のみ。新規プロジェクトの雛形（フォント・CSS・原稿サンプル）は
  # lib/project_scaffold/ に集約されているため、リポジトリ直下の config/ や stylesheets/
  # （このリポジトリ自身の書籍ビルド用）は配布物に含めない。
  # FNM_DOTMATCH は scaffold 内の .gitignore / .textlintrc.yml を拾うために必要。
  spec.files = Dir.glob('{bin,lib}/**/*', File::FNM_DOTMATCH)
                  .select { |f| File.file?(f) }
                  .reject { |f| File.basename(f) == '.DS_Store' }
  spec.files += %w[README.md LICENSE THIRD-PARTY-LICENSES.md]
  spec.bindir        = 'bin'
  spec.executables   = %w[vivlio-starter vs]
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'query-stream', '~> 1.2.2'
  spec.add_dependency 'combine_pdf', '~> 1.0'
  spec.add_dependency 'kramdown', '~> 2.4'
  spec.add_dependency 'mini_magick', '~> 4.12'
  spec.add_dependency 'nokogiri', '~> 1.16'
  spec.add_dependency 'pdf-reader', '~> 2.12'
  spec.add_dependency 'prawn', '~> 2.5'
  spec.add_dependency 'samovar', '~> 2.1'
  spec.add_dependency 'rouge', '~> 4.7'

  # Optional: 索引機能の読み自動推測に使用（MeCab が必要）
  # MeCab をシステムにインストールした上で使用:
  #   macOS: brew install mecab mecab-ipadic
  #   Ubuntu: sudo apt-get install mecab libmecab-dev mecab-ipadic-utf8
  spec.add_dependency 'natto', '~> 1.2'

  # Development dependencies
  spec.add_development_dependency 'rake', '~> 13.2'
  spec.add_development_dependency 'rubocop', '~> 1.65'
  spec.add_development_dependency 'minitest', '~> 5.22'
  spec.metadata['rubygems_mfa_required'] = 'false'
end
