class Libogg < Formula
  desc "Ogg Bitstream Library"
  homepage "https://www.xiph.org/ogg/"
  url "https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-1.3.5.tar.gz"
  sha256 "0eb4b4b9420a0f51db142ba3f9c64b333f826532dc0f48c6410ae51f4799b664"
  license "BSD-3-Clause"
  head "https://gitlab.xiph.org/xiph/ogg.git", branch: "master"

  depends_on "cmake" => :build

  resource("oggfile") do
    url "https://upload.wikimedia.org/wikipedia/commons/c/c8/Example.ogg"
    sha256 "f57b56d8aae4c847cf01224fb45293610d801cfdac43d932b5eeab1cd318182a"
  end

  def install
    system "cmake", "-S", ".", "-B", "build", "-DBUILD_SHARED_LIBS=TRUE", *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
    system "cmake", "-S", ".", "-B", "build-static", "-DBUILD_SHARED_LIBS=FALSE", *std_cmake_args
    system "cmake", "--build", "build-static"
    lib.install "build-static/libogg.a"
  end

  test do
    (testpath/"test.c").write <<~EOS
      #include <ogg/ogg.h>
      #include <stdio.h>

      int main (void) {
        ogg_sync_state oy;
        ogg_stream_state os;
        ogg_page og;
        ogg_packet op;
        char *buffer;
        int bytes;

        ogg_sync_init (&oy);
        buffer = ogg_sync_buffer (&oy, 4096);
        bytes = fread(buffer, 1, 4096, stdin);
        ogg_sync_wrote (&oy, bytes);
        if (ogg_sync_pageout (&oy, &og) != 1)
          return 1;
        ogg_stream_init (&os, ogg_page_serialno (&og));
        if (ogg_stream_pagein (&os, &og) < 0)
          return 1;
        if (ogg_stream_packetout (&os, &op) != 1)
         return 1;

        return 0;
      }
    EOS
    testpath.install resource("oggfile")
    system ENV.cc, "test.c", "-I#{include}", "-L#{lib}", "-logg",
                   "-o", "test"
    # Should work on an OGG file
    shell_output("./test < Example.ogg")
    # Expected to fail on a non-OGG file
    shell_output("./test < #{test_fixtures("test.wav")}", 1)
  end
end
