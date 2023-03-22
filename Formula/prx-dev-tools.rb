class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.25.tar.gz"
  sha256 "61e1be33d0c4ad6f95dfd7b8ee80efe37bcc24523d551a8c5b817b971783fdc9"
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
