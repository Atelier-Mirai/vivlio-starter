# frozen_string_literal: true

require_relative "lib/vivlio/starter/version"

Gem::Specification.new do |spec|
  spec.name          = "vivlio-starter"
  spec.version       = Vivlio::Starter::VERSION
  spec.authors       = ["Atelier Mirai"]
  spec.email         = ["contact@atelier-mirai.net"]

  spec.summary       = "Vivlio Starter: Build pipeline and CLI for Vivliostyle-based books"
  spec.description   = "Provides Rake tasks and a CLI to preprocess, convert, and build books using Vivliostyle."
  spec.homepage      = "https://github.com/Atelier-Mirai/vivlio-starter"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0"

  # Files
  if File.exist?(".git") && system("git --version > /dev/null 2>&1")
    spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  else
    spec.files = Dir.glob("{bin,lib,stylesheets,contents,images,templates,config,rakelib}/**/*", File::FNM_DOTMATCH)
    spec.files += %w[README.md LICENSE Rakefile Gemfile]
  end
  spec.bindir        = "bin"
  spec.executables   = ["vivlio-starter", "vs"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_runtime_dependency "kramdown", "~> 2.4"
  spec.add_runtime_dependency "nokogiri", "~> 1.16"
  spec.add_runtime_dependency "hexapdf", "~> 1.0"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "bundler", "~> 2.5"
end
