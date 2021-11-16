class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.1.tar.gz"
  sha256 "6aa1850089c5de68003e06c542798e6091c71dbe6b79138587528904f47e4fe0"
  license ""

  def install
    bin.install "bin/awssh-beta"
  end

  test do
    assert_match "awssh 0.0.1", shell_output("#{bin}/awssh-beta -v", 2)
  end
end
