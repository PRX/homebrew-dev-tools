class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.1.6.tar.gz"
  sha256 "544df28d78fc0dafa8ad79a1964bbbadf8797523c9b54bf959537a390c9f7c22"
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
