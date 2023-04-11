class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.1.4.tar.gz"
  sha256 "48a4b8da537e2d77ce8d46db542551588fc7edad3b5747e7490a28289f36c80f"
  license ""

  def install
    bin.install "bin/awssh"
    bin.install "bin/awsso.rb" => "awsso"
    bin.install "bin/awstunnel"
    bin.install "bin/prx-github-repo-audit.rb" => "prx-github-repo-audit"
    bin.install "bin/prxameter-list.rb" => "prxameter-list"
    bin.install "bin/prxameter-check-sync.rb" => "prxameter-check-sync"
    bin.install "bin/prxameter-region-sync.rb" => "prxameter-region-sync"
    bin.install "bin/prxameter-check-promotion.rb" => "prxameter-check-promotion"
    bin.install "bin/prx-cfn-tree.rb" => "prx-cfn-tree"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
