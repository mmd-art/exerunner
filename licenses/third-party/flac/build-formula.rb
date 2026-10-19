class Flac < Formula
  desc "Free lossless audio codec"
  homepage "https://xiph.org/flac/"
  url "https://downloads.xiph.org/releases/flac/flac-1.5.0.tar.xz", using: :homebrew_curl
  mirror "https://ftp.osuosl.org/pub/xiph/releases/flac/flac-1.5.0.tar.xz"
  sha256 "f2c1c76592a82ffff8413ba3c4a1299b6c7ab06c734dee03fd88630485c2b920"
  license all_of: [
    "BSD-3-Clause",
    "GPL-2.0-or-later",
    "ISC",
    "LGPL-2.0-or-later",
    "LGPL-2.1-or-later",
    :public_domain,
    any_of: ["GPL-2.0-or-later", "LGPL-2.1-or-later"],
  ]

  livecheck do
    url "https://ftp.osuosl.org/pub/xiph/releases/flac/?C=M&O=D"
    regex(/href=.*?flac[._-]v?(\d+(?:\.\d+)+)\.t/i)
  end

  head do
    url "https://gitlab.xiph.org/xiph/flac.git"

    depends_on "autoconf" => :build
    depends_on "automake" => :build
    depends_on "libtool" => :build
  end

  depends_on "pkgconf" => :build
  depends_on "libogg"

  def install
    system "./autogen.sh" if build.head?
    system "./configure", "--enable-static", *std_configure_args
    system "make", "install"
  end

  test do
    system bin/"flac", "--decode", "--force-raw", "--endian=little", "--sign=signed",
                       "--output-name=out.raw", test_fixtures("test.flac")
    system bin/"flac", "--endian=little", "--sign=signed", "--channels=1", "--bps=8",
                       "--sample-rate=8000", "--output-name=out.flac", "out.raw"
  end
end
