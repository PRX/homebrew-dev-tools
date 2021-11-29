class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.3.tar.gz"
  sha256 "589d8990699562c0574ff79ecce97f52fa4f9ccddba8e10265609233fa650621"
  license ""

  def install
    bin.install "bin/awssh"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
