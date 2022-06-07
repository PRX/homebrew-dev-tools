class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.11.tar.gz"
  sha256 "e196f575394e5760eedcb268b23f076ed80a8aa90c0fa2445624d7799b94de95"
  license ""

  def install
    bin.install "bin/awssh"
    bin.install "bin/awstunnel"
    bin.install "bin/prxameter-check-sync"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
