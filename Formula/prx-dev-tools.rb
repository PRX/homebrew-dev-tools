class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.0.10.tar.gz"
  sha256 "623b46753e07342b490c22bcf76fe3d21d2704bff13d70bbf7de136601776462"
  license ""

  def install
    bin.install "bin/awssh"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
