class FileSnitch < Formula
  desc "Guarded FUSE mounts for a user's secret-bearing files"
  homepage "https://github.com/pkoch/file-snitch"
  # stable-release-start
  url "https://github.com/pkoch/file-snitch/releases/download/v0.5.0/file-snitch-0.5.0-source.tar.gz"
  sha256 "c0f64242c5d5027441ddda7e600551743131f0155e2155eb2f29c3e72e064e7f"
  # stable-release-end
  head "https://github.com/pkoch/file-snitch.git", branch: "master"

  bottle do
    root_url "https://github.com/pkoch/homebrew-tap/releases/download/file-snitch-0.5.0"
    sha256                               arm64_tahoe:  "d5914bbd4090d3e85eeefbd46a59a786cfbeba617428bbb7912e8fa89d3281ef"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "9fd004f01c65c862d63ae195cd936277b19ffa8e679ebe6a0a16a1df860675f3"
  end

  depends_on "pkgconf" => :build
  depends_on "zig@0.16" => :build
  depends_on "libfuse" if OS.linux?
  depends_on "pass"

  resource "macfuse" do
    on_macos do
      url "https://github.com/macfuse/macfuse/releases/download/macfuse-5.1.1/macfuse-5.1.1.dmg"
      sha256 "cdd60135ba49467e6f17cbf97d843d7d9e0ab0eda022861d39deaa3cee53e359"
    end
  end

  def install
    sdk_root = stage_macfuse_sdk if OS.mac?
    system "zig", "build", *std_zig_args
    install_private_macfuse(sdk_root) if OS.mac?
  end

  def caveats
    <<~EOS
      file-snitch currently assumes:
        * a working `pass` setup
        * a usable GPG environment for `pass`
        * FUSE support installed outside Homebrew

      On macOS, install macFUSE separately before building or running.

      Prompting is handled by the local agent service. Bootstrap it
      manually with:

        file-snitch agent
        file-snitch run prompt

      For per-user service setup, see:

        https://github.com/pkoch/file-snitch/blob/master/docs/services.md
    EOS
  end

  test do
    output = shell_output("#{bin}/file-snitch version 2>&1")
    assert_match "file-snitch", output
  end

  private

  def stage_macfuse_sdk
    sdk_root = buildpath/"macfuse-sdk"

    macfuse = resource("macfuse")
    macfuse.fetch
    dmg = macfuse.cached_download
    mountpoint = Utils.safe_popen_read("hdiutil", "attach", "-nobrowse", "-readonly", "-plist", dmg).then do |plist|
      plist[%r{<key>mount-point</key>\s*<string>([^<]+)</string>}, 1]
    end
    odie "failed to mount macFUSE DMG" if mountpoint.blank?

    begin
      pkg_path = "#{mountpoint}/Extras/macFUSE 5.1.1.pkg"
      system "pkgutil", "--expand-full", pkg_path, buildpath/"macfuse-pkg"
      mkdir_p sdk_root/"include"
      mkdir_p sdk_root/"lib"
      cp_r (buildpath/"macfuse-pkg/Core.pkg/Payload/usr/local/include/.").children, sdk_root/"include"
      cp_r (buildpath/"macfuse-pkg/Core.pkg/Payload/usr/local/lib/.").children, sdk_root/"lib"
    ensure
      system "hdiutil", "detach", mountpoint
    end

    ENV["FILE_SNITCH_FUSE_INCLUDE_DIR"] = (sdk_root/"include").to_s
    ENV["FILE_SNITCH_FUSE_LIB_DIR"] = (sdk_root/"lib").to_s
    sdk_root
  end

  def install_private_macfuse(sdk_root)
    private_dylib = libexec/"libfuse.2.dylib"
    libexec.install sdk_root/"lib/libfuse.2.dylib"
    MachO::Tools.change_dylib_id(private_dylib, "@loader_path/libfuse.2.dylib")
    MachO::Tools.change_install_name(bin/"file-snitch",
                                     "/usr/local/lib/libfuse.2.dylib",
                                     "@loader_path/../libexec/libfuse.2.dylib")
  end
end
