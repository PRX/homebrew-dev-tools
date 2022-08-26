class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.18.tar.gz"
  sha256 "7d8a4e2dbde83488c175dd229239d6d7095add9576a27e016e12e356268122cb"
  license ""

  def install
    bin.install "bin/awssh"
    bin.install "bin/awstunnel"
    bin.install "bin/prxameter-check-sync"
    bin.install "bin/prxameter-region-sync"
    bin.install "bin/prx-repo-audit"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
