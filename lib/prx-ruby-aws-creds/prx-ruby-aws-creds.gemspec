Gem::Specification.new do |s|
  s.name = "prx-ruby-aws-creds"
  s.version = "0.1.3"
  s.summary = "tktk"
  s.description = "tktk"
  s.authors = ["Christopher Kalafarski"]
  s.email = "chris.kalafarski@prx.org"
  s.files = ["lib/prx-ruby-aws-creds.rb"]
  s.homepage = "https://github.com/PRX/homebrew-dev-tools/tree/main/lib/prx-ruby-aws-creds"
  s.license = "MIT"

  s.add_runtime_dependency "inifile"
  s.add_runtime_dependency "nokogiri"
  s.add_runtime_dependency "aws-sdk-core"
  s.add_runtime_dependency "aws-sdk-sso"
  s.add_runtime_dependency "aws-sdk-sts"
end
