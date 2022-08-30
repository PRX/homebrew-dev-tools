class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.22.tar.gz"
  sha256 "2e7a3dc2d94644512329c2f9e2c97b9de188987201978301c672649112fd8692"
  license ""

  def install
    bin.install "bin/awssh"
    bin.install "bin/awstunnel"
    bin.install "bin/prxameter-list"
    bin.install "bin/prxameter-check-sync"
    bin.install "bin/prxameter-region-sync"
    bin.install "bin/prx-repo-audit"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
