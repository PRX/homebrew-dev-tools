#!/usr/bin/env ruby

require "bundler/inline"
require "json"
require "io/console"
require "fileutils"
require "digest"
require "base64"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "terminal-table"
  gem "octokit"
  gem "slop"
  gem "faraday-retry"
  gem "tty-spinner"
end

OPTS = Slop.parse do |o|
  o.string "--token", "Personal access token", required: true
  o.on "-h", "--help" do
    puts o
    exit
  end
end

CLIENT = Octokit::Client.new(access_token: OPTS[:token])

repos = [
  "PRX/Infrastructure",
  "PRX/feeder.prx.org",
  "PRX/corporate.prx.org",
  "PRX/dovetail-marketing-site",
  "PRX/Porter",
  "PRX/play-proxy",
  "PRX/networks.prx.org",
  "PRX/cms.prx.org",
  "PRX/castle.prx.org",
  "PRX/TheCastle",
  "PRX/iframely",
  "PRX/remix-select",
  "PRX/play.prx.org",
  "PRX/styleguide.prx.org",
  "PRX/wfmt-services",
  "PRX/the-count",
  "PRX/search.theworld.org",
  "PRX/upload.prx.org",
  "PRX/proxy.prx.org",
  "PRX/tower.radiotopia.fm",
  "PRX/beta.prx.org",
  "PRX/dovetail-counts-lambda",
  "PRX/dovetail-cdn-origin-request",
  "PRX/dovetail-traffic-lambda",
  "PRX/analytics-ingest-lambda",
  "PRX/exchange-ftp-authorizer",
  "PRX/dovetail-metrics-export",
  "PRX/metrics.prx.org",
  "PRX/dovetail-router.prx.org",
  "PRX/augury.prx.org",
  "PRX/exchange.prx.org",
  "PRX/dovetail-cdn-arranger",
  "PRX/id.prx.org",
  "PRX/publish.prx.org",
  "PRX/.github",
  "PRX/Play-Next.js",
  "PRX/theworld.org",
  "PRX/internal",
  "PRX/prx-wavefile",
  "PRX/api-bridge-lambda",
  "PRX/halbuilder",
  "PRX/passenger-list",
  "PRX/homebrew-dev-tools",
  "PRX/cms.theworld.org",
  "PRX/www.radiotopia.fm",
  "PRX/prx_auth-rails",
  "PRX/redix-clustered",
  "PRX/dovetail-cdn-viewer-request",
  "PRX/annual-report-2021",
  "PRX/meta.prx.org",
  "PRX/docs.prx.org",
  "PRX/activewarehouse",
  "PRX/prx_auth",
  "PRX/hal_api-rails",
  "PRX/prx_access",
  "PRX/announce",
  "PRX/prx-podagent",
  "PRX/radio.radiotopia.fm",
  "PRX/open_calais",
  "PRX/prx-ng-serve",
  "PRX/prx_auth-elixir",
  "PRX/prx_access-elixir",
  "PRX/loadingdock.prx.org"
]

rows = []

def get_tool_version(contents, runtime)
  match = Regexp.new("#{runtime} ([0-9.]+)").match(contents)
  match[1] if match
end

def get_elixir_version(repo)
  res = CLIENT.contents(repo, path: ".tool-versions")
  get_tool_version(Base64.decode64(res.content).strip, "elixir")
rescue Octokit::NotFound
end

def get_erlang_version(repo)
  res = CLIENT.contents(repo, path: ".tool-versions")
  get_tool_version(Base64.decode64(res.content).strip, "erlang")
rescue Octokit::NotFound
end

def get_ruby_version(repo)
  res = CLIENT.contents(repo, path: ".ruby-version")
  Base64.decode64(res.content).strip
rescue Octokit::NotFound
  begin
    res = CLIENT.contents(repo, path: ".tool-versions")
    get_tool_version(Base64.decode64(res.content).strip, "ruby")
  rescue Octokit::NotFound
  end
end

def get_rails_version(repo)
  res = CLIENT.contents(repo, path: "Gemfile.lock")
  content = Base64.decode64(res.content)
  match = /\srails\s\(([0-9.]+)\)/.match(content)
  match[1] if match
rescue Octokit::NotFound
end

def get_node_version(repo)
  res = CLIENT.contents(repo, path: ".nvmrc")
  Base64.decode64(res.content).strip
rescue Octokit::NotFound
  begin
    res = CLIENT.contents(repo, path: ".tool-versions")
    get_tool_version(Base64.decode64(res.content).strip, "nodejs")
  rescue Octokit::NotFound
  end
end

spinner = TTY::Spinner.new("[:spinner] Auditing #{repos.length} repositories. This will take a few minutes…", format: :dots, clear: true)
spinner.auto_spin

headings = ["Repository", "Visibility", "License", "Ruby", "Rails", "Node.js", "Elixir", "Erlang"]
repos.each do |repo|
  info = CLIENT.repository(repo)
  # pp info.license

  visibility = info.private ? "Private".yellow : "Public".blue

  ruby_version = get_ruby_version(repo)
  rails_version = get_rails_version(repo)
  node_version = get_node_version(repo)
  elixir_version = get_elixir_version(repo)
  erlang_version = get_erlang_version(repo)
  rows.push([info.name, visibility, info.license&.spdx_id, ruby_version, rails_version, node_version, elixir_version, erlang_version])
end

spinner.stop("Done!")
puts Terminal::Table.new headings: headings, rows: rows
