class Stay < Formula
  desc "Terminal session manager for persistent tmux sessions"
  homepage "https://github.com/nevdelap/stay"
  license "MIT"
  depends_on "tmux"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/nevdelap/stay/releases/download/v0.0.86/stay-v0.0.86-aarch64-apple-darwin.tar.gz"
      sha256 "5e313ab7dbbe53329635587551a22f39f5b61f18de0d72d886363b88facedee0"
    else
      url "https://github.com/nevdelap/stay/releases/download/v0.0.86/stay-v0.0.86-x86_64-apple-darwin.tar.gz"
      sha256 "bd9793b85d13da05472e634418d3722f7d8b3b038a3b125a0abe8d36d86fbe2a"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/nevdelap/stay/releases/download/v0.0.86/stay-v0.0.86-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "9daf0b200f696c646b20b2a1c1b5905bbda6771ccb663ebb058329b4d0f640da"
    else
      url "https://github.com/nevdelap/stay/releases/download/v0.0.86/stay-v0.0.86-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "64c63305fefacb696647880b7cf30baf94e9c10365630878f03d4adf2e4c02ce"
    end
  end

  def install
    bin.install "stay"
  end

  test do
    require "json"

    ENV.delete("TMUX")
    original_path = ENV.fetch("PATH")
    original_tmux_tmpdir = ENV["TMUX_TMPDIR"]
    tmux_tmpdir = testpath / "tmux-tmpdir"
    tmux_tmpdir.mkpath
    ENV["TMUX_TMPDIR"] = tmux_tmpdir.to_s
    socket_dir = tmux_tmpdir / "tmux-#{Process.uid}"
    socket_path = socket_dir / "stay"
    session = "stay-homebrew-test"

    begin
      assert_equal "stay #{version}", shell_output("#{bin}/stay --version").strip

      inventory = JSON.parse(shell_output("#{bin}/stay list --json"))
      assert_equal [], inventory.fetch("sessions")

      system bin / "stay", "create", session, "--", "sleep", "30"
      inventory = JSON.parse(shell_output("#{bin}/stay list --json"))
      assert_equal [session], inventory.fetch("sessions").map { |row| row.fetch("name") }

      system bin / "stay", "kill", session
      inventory = JSON.parse(shell_output("#{bin}/stay list --json"))
      assert_equal [], inventory.fetch("sessions")

      server_probe = shell_output("tmux -L stay list-sessions 2>&1", 1)
      assert_match "no server running", server_probe
      rm socket_path if socket_path.exist?
      refute_path_exists socket_path
      rm_r tmux_tmpdir
      refute_path_exists tmux_tmpdir

      fake_tmux = testpath / "fake-tmux"
      fake_tmux.mkpath
      fake_tmux_bin = fake_tmux / "tmux"
      fake_tmux_bin.write("#!/bin/sh\nprintf 'tmux 3.5\\n'\n")
      fake_tmux_bin.chmod(0755)
      ENV["PATH"] = "#{fake_tmux}:#{original_path}"
      assert_match "tmux 3.6 or newer",
                   shell_output("#{bin}/stay list --json 2>&1", 1)
    ensure
      ENV["PATH"] = original_path
      if tmux_tmpdir.exist?
        Kernel.system "tmux", "-L", "stay", "kill-server"
        rm_r tmux_tmpdir
      end
      if original_tmux_tmpdir
        ENV["TMUX_TMPDIR"] = original_tmux_tmpdir
      else
        ENV.delete("TMUX_TMPDIR")
      end
    end
  end
end
