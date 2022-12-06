class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.24.tar.gz"
  sha256 "10b0bf80a1ae3df760dc72668657acd06bb9444a8f81242f470e42a2c5f37766"
  license ""

  def install
    bin.install "bin/awssh"
    bin.install "bin/awsso"
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
