class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.14.tar.gz"
  sha256 "8f2efa8c4a9fc7747dc3cc4d276edf4c140dd7effade10d134fd9148f52edf81"
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
