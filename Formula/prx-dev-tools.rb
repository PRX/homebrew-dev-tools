class PrxDevTools < Formula
  desc "PRX developer tools"
  homepage "https://github.com/PRX/homebrew-dev-tools"
  url "https://github.com/PRX/homebrew-dev-tools/archive/refs/tags/v0.2.3.tar.gz"
  sha256 "b10d05e622a07c08cbf20b1135fabffdf502caf5abce77f979cc0b6ac6be05d4"
  license ""

  def install
    bin.install "bin/awssh"
    bin.install "src/awsso.rb" => "awsso"
    bin.install "bin/awstunnel"
    bin.install "src/prx-cfn-tree.rb" => "prx-cfn-tree"
    bin.install "src/prx-empty-log-groups.rb" => "prx-empty-log-groups"
    bin.install "src/prx-github-repo-audit.rb" => "prx-github-repo-audit"
    bin.install "src/prx-immortal-log-groups.rb" => "prx-immortal-log-groups"
    bin.install "src/prx-reservations.rb" => "prx-reservations"
    bin.install "src/prxameter-audit-usage.rb" => "prxameter-audit-usage"
    bin.install "src/prxameter-check-promotion.rb" => "prxameter-check-promotion"
    bin.install "src/prxameter-check-sync.rb" => "prxameter-check-sync"
    bin.install "src/prxameter-list.rb" => "prxameter-list"
    bin.install "src/prxameter-region-sync.rb" => "prxameter-region-sync"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/awssh -v", 2)
  end
end
