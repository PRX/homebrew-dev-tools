class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.2.6.tar.gz"
  sha256 "af3c217ea337690ba7f93b31c3cff8b86531da6309d2168762330a99d0e5ecb2"
  license ""

  def install
    bin.install "bin/awssh"
    bin.install "bin/awsso.rb" => "awsso"
    bin.install "bin/awstunnel"
    bin.install "bin/prx-cfn-tree.rb" => "prx-cfn-tree"
    bin.install "bin/prx-empty-log-groups.rb" => "prx-empty-log-groups"
    bin.install "bin/prx-github-repo-audit.rb" => "prx-github-repo-audit"
    bin.install "bin/prx-immortal-log-groups.rb" => "prx-immortal-log-groups"
    bin.install "bin/prx-reservations.rb" => "prx-reservations"
    bin.install "bin/prxameter-audit-usage.rb" => "prxameter-audit-usage"
    bin.install "bin/prxameter-check-promotion.rb" => "prxameter-check-promotion"
    bin.install "bin/prxameter-check-sync.rb" => "prxameter-check-sync"
    bin.install "bin/prxameter-list.rb" => "prxameter-list"
    bin.install "bin/prxameter-region-sync.rb" => "prxameter-region-sync"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
