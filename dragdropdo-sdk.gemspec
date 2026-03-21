Gem::Specification.new do |spec|
  spec.name          = "dragdropdo-sdk"
  spec.version       = "1.0.0"
  spec.authors       = ["Dragdropdo"]
  spec.email         = ["hi@dragdropdo.com"]

  spec.summary       = "Official Ruby client library for the Dragdropdo Business API"
  spec.description   = "Official Ruby client library for the Dragdropdo Business API. Provides a simple and elegant interface for developers to interact with Dragdropdo's file processing services."
  spec.homepage      = "https://github.com/dragdropdo/dragdropdo-sdk-ruby"
  spec.license       = "ISC"

  spec.metadata = {
    "homepage_uri"      => "https://dragdropdo.com",
    "source_code_uri"   => "https://github.com/dragdropdo/dragdropdo-sdk-ruby",
    "bug_tracker_uri"   => "https://github.com/dragdropdo/dragdropdo-sdk-ruby/issues",
    "changelog_uri"     => "https://github.com/dragdropdo/dragdropdo-sdk-ruby/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://docs.dragdropdo.com",
    "wiki_uri"          => "https://github.com/dragdropdo/dragdropdo-sdk-ruby/wiki",
    "mailing_list_uri"  => "https://dragdropdo.com/company",
    "funding_uri"       => "https://dragdropdo.com/about-us"
  }

  spec.files         = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-multipart", "~> 1.0"

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end

