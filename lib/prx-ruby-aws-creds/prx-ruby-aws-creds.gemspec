lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |s|
  s.name = "prx-ruby-aws-creds"
  s.version = "0.3.0"
  s.summary = "tktk"
  s.description = "tktk"
  s.authors = ["Christopher Kalafarski"]
  s.email = "chris.kalafarski@prx.org"
  s.files = ["lib/prx-ruby-aws-creds.rb"]
  s.homepage = "https://github.com/PRX/homebrew-dev-tools/tree/main/lib/prx-ruby-aws-creds"
  s.license = "MIT"

  s.require_paths = ["lib"]

  s.add_dependency "inifile", "~> 3.0"
  s.add_dependency "nokogiri"
  s.add_dependency "aws-sdk-core"
  s.add_dependency "aws-sdk-sso"
  s.add_dependency "aws-sdk-sts"
end
