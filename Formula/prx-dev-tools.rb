class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.9.tar.gz"
  sha256 "5cb6e05757fa4b732b82bb2e76193882064a253937e5ac2048469e3d3a748167"
  license ""

  def install
    bin.install "bin/awssh"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
