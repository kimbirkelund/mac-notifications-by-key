# Homebrew formula for nbk.
#
# This is a TEMPLATE. To publish: create a personal tap repo (e.g.
# `kimbirkelund/homebrew-tap`), copy this file to `Formula/nbk.rb` there, and on
# each release bump `version` + `sha256` to the values the Release workflow prints
# in the GitHub Release notes. Users then install with:
#
#   brew install kimbirkelund/tap/nbk
#
# The url interpolates the release tag `releases/v<version>` and the universal
# tarball name produced by `build.ps1 -DoPackage`.
class Nbk < Formula
  desc "Keyboard-driven control of macOS notifications via the Accessibility API"
  homepage "https://github.com/kimbirkelund/mac-notifications-by-key"
  version "0.0.0"
  url "https://github.com/kimbirkelund/mac-notifications-by-key/releases/download/releases/v#{version}/nbk-#{version}-macos-universal.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  depends_on :macos

  def install
    bin.install "nbk"
  end

  def caveats
    <<~EOS
      nbk drives the macOS Notification Center through the Accessibility API, so the
      process that runs it (your terminal, or skhd) must be granted Accessibility
      permission:

        System Settings → Privacy & Security → Accessibility

      Check status any time with:  nbk doctor
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/nbk --version")
  end
end
