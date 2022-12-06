class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.23.tar.gz"
  sha256 "b104d8919f24d9b7c4a70d0e02db9c22cba0c73078137914432db5ef36bea6c3"
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
