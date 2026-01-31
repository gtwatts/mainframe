# Homebrew formula for MAINFRAME
# Install: brew install gtwatts/mainframe/mainframe

class Mainframe < Formula
  desc "Pure bash standard library with 4,000+ functions for AI coding agents"
  homepage "https://github.com/gtwatts/mainframe"
  url "https://github.com/gtwatts/mainframe/archive/refs/tags/v6.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"
  head "https://github.com/gtwatts/mainframe.git", branch: "main"

  depends_on "bash" => "4.4"

  def install
    # Install libraries to libexec
    libexec.install "lib"
    libexec.install "scripts"
    libexec.install "skills"
    libexec.install "hooks"
    libexec.install "completions" if Dir.exist?("completions")
    libexec.install "CHEATSHEET.md"
    libexec.install "CLAUDE.md"

    # Create main entry point
    (bin/"mainframe").write <<~EOS
      #!/usr/bin/env bash
      export MAINFRAME_ROOT="#{libexec}"
      exec "#{libexec}/lib/common.sh" "$@"
    EOS

    # Create shell initialization script
    (libexec/"init.sh").write <<~EOS
      # MAINFRAME Shell Initialization
      # Add to your ~/.bashrc or ~/.zshrc:
      #   source "$(brew --prefix)/opt/mainframe/libexec/init.sh"

      export MAINFRAME_ROOT="#{libexec}"
      export MAINFRAME_AI_ENABLED=1
      export MAINFRAME_VERSION="6.0"

      # Source MAINFRAME in current shell (optional)
      # source "$MAINFRAME_ROOT/lib/common.sh"
    EOS
  end

  def caveats
    <<~EOS
      MAINFRAME installed successfully!

      To use in bash scripts, add this line at the top:
        source "#{libexec}/lib/common.sh"

      Or set up shell integration by adding to your ~/.bashrc or ~/.zshrc:
        source "$(brew --prefix)/opt/mainframe/libexec/init.sh"

      Quick test:
        source "#{libexec}/lib/common.sh" && json_object "status=ok"

      Documentation:
        #{libexec}/CHEATSHEET.md - All 4,000+ function signatures
        #{libexec}/CLAUDE.md - AI coding assistant instructions

      AI Discovery:
        Run 'mainframe ai-discovery setup' to configure AI tool auto-detection.
    EOS
  end

  test do
    # Test that common.sh can be sourced
    assert_match "MAINFRAME", shell_output("source #{libexec}/lib/common.sh && echo MAINFRAME")

    # Test a basic function
    assert_match "hello", shell_output("source #{libexec}/lib/common.sh && to_lower 'HELLO'")
  end
end
