# Homebrew formula for nbk (stable channel).
#
# Source of truth. The Release workflow (.github/workflows/release.yml) rewrites
# `version` + `sha256` from the published release and copies this file into the
# tap repo at kimbirkelund/homebrew-tap:Formula/nbk.rb on every final release.
# The `url` interpolates `#{version}` against the `release/v<version>` tag and the
# universal tarball name produced by `build.ps1 -DoPackage`, so it needs no bump.
#
# Install:  brew install kimbirkelund/tap/nbk
class Nbk < Formula
  desc "Keyboard-driven control of macOS notifications via the Accessibility API"
  homepage "https://github.com/kimbirkelund/mac-notifications-by-key"
  version "1.0.4"
  url "https://github.com/kimbirkelund/mac-notifications-by-key/releases/download/release/v#{version}/nbk-#{version}-macos-universal.tar.gz"
  sha256 "e56ef9ce2e0036be98e5ce6cd684567bf6366bff1c6d980b513bd2231f1b9db5"
  depends_on :macos
  conflicts_with "nbk-beta", because: "both install a `nbk` binary"

  def install
    bin.install "nbk"
  end

  def caveats
    <<~EOS
      nbk drives the macOS Notification Center through the Accessibility API, so the
      process that runs it (your terminal, or skhd) must be granted Accessibility
      permission:

        System Settings → Privacy & Security → Device Control and Data Access ("Accessibility" on older macOS)

      Check status any time with:  nbk doctor
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/nbk --version")
  end
end
