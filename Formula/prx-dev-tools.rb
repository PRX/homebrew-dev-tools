class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.17.tar.gz"
  sha256 "87ceb2c5bd696e7b7e6fa4db55b1d04230b62d7be404e16a2dbe9f85c71acade"
  license ""

  def install
    bin.install "bin/awssh"
    bin.install "bin/awstunnel"
    bin.install "bin/prxameter-check-sync"
    bin.install "bin/prxameter-region-sync"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
