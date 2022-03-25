class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.8.tar.gz"
  sha256 "42d52db94b1a61e94edbf4a96ea2630dda661c0af79304625785ff840c866ec5"
  license ""

  def install
    bin.install "bin/awssh"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
