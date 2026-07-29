class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.3.8.tar.gz"
  sha256 "3765107a10f52eed20c83e48831ff1d0d888f3f34cf03c7235fe9daf39c15342"
  license ""

  def install
    bin.install "bin/awsesh.rb" => "awsesh"
    bin.install "bin/awsso.rb" => "awsso"
    bin.install "bin/awstunnel"
    bin.install "bin/prx-cfn-tree.rb" => "prx-cfn-tree"
    bin.install "bin/prx-dovetail-regions.rb" => "prx-dovetail-regions"
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
