class Zepto < Formula
  desc "Modern, intuitive terminal text editor — single file, no dependencies"
  homepage "https://zepto.now"
  url "https://github.com/joewalnes/zepto/releases/download/latest/zepto"
  version "latest"
  license "MIT"

  def install
    bin.install "zepto"
  end

  test do
    assert_match "zepto", shell_output("#{bin}/zepto --version 2>&1", 0)
  end
end
