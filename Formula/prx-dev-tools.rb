class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.2.tar.gz"
  sha256 "839e32f6b37f4f1a5fc78e0a5ef038ba9666adbc0f5e6b40c69c4cd1fe6b8c3d"
  license ""

  def install
    bin.install "bin/awssh"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
