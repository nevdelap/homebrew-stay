class Stay < Formula
  desc "Terminal session manager for persistent tmux sessions"
  homepage "https://github.com/nevdelap/stay"
  license "MIT"
  depends_on "tmux"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/nevdelap/stay/releases/download/v0.0.99/stay-v0.0.99-aarch64-apple-darwin.tar.gz"
      sha256 "20b6d97de53e0d0a7881d58f78987ada39c3984bd4643663bebb4137b1c93f26"
    else
      url "https://github.com/nevdelap/stay/releases/download/v0.0.99/stay-v0.0.99-x86_64-apple-darwin.tar.gz"
      sha256 "7fcbf5e2a33d6a8e37756a4c9e770cc2d4d53347fa914ab0b7bbdcbcc5642b32"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/nevdelap/stay/releases/download/v0.0.99/stay-v0.0.99-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "4bdb5e5a796f3c23c838ed0f29799e5bab29362fd55e67cf4195a43eb07d3793"
    else
      url "https://github.com/nevdelap/stay/releases/download/v0.0.99/stay-v0.0.99-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "1335128395d5bad4f14af641021a1f6f4bce6fbc825c05ca8d71b225aafec664"
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
