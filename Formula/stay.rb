class Stay < Formula
  desc "Terminal session manager for persistent tmux sessions"
  homepage "https://github.com/nevdelap/stay"
  license "MIT"
  depends_on "tmux"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/nevdelap/stay/releases/download/v0.0.88/stay-v0.0.88-aarch64-apple-darwin.tar.gz"
      sha256 "6a0a215097a49a634e9620c33553132b0f3ad78bdcd007c30d6b64921ace6eab"
    else
      url "https://github.com/nevdelap/stay/releases/download/v0.0.88/stay-v0.0.88-x86_64-apple-darwin.tar.gz"
      sha256 "9583e27ae12228f83db15fa72f319b3faf62639e64b56e9aa389bec58fec18f8"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/nevdelap/stay/releases/download/v0.0.88/stay-v0.0.88-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "b41d5260b60163dad245466a49d44d47f0b19b3a4725079bd17bc7e6b5921022"
    else
      url "https://github.com/nevdelap/stay/releases/download/v0.0.88/stay-v0.0.88-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "5560913eefda4dccb7b357f34e3fe41160cc6d27a149a75985f502e52c91a022"
    end
  end

  def install
    bin.install "stay"
    man1.install "stay.1"
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

      man_path = Pathname.new(shell_output("man -w stay").strip)
      assert_path_exists man_path
      assert_equal "stay.1", man_path.basename.to_s
      assert_match "STAY(1)", shell_output("MANPAGER=cat man stay")

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
