class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.15.tar.gz"
  sha256 "7d54efa7b200735be1b267d535d746d195d72bac888e3d5c537e03c2223b2f1f"
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
