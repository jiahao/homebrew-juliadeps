require 'formula'

class Glib < Formula
  homepage 'http://developer.gnome.org/glib/'
  url 'http://ftp.gnome.org/pub/gnome/sources/glib/2.38/glib-2.38.2.tar.xz'
  sha256 '056a9854c0966a0945e16146b3345b7a82562a5ba4d5516fd10398732aea5734'

  option :universal
  option 'test', 'Build a debug build and run tests. NOTE: Not all tests succeed yet'

  bottle do
    root_url 'http://archive.org/download/julialang/bottles'
    cellar :any
    sha1 'f72ea3b73f27f669c7c836317dd93a08ba33355c' => :snow_leopard_or_later
  end

  depends_on 'staticfloat/juliadeps/pkg-config' => :build
  depends_on 'xz' => :build
  depends_on 'staticfloat/juliadeps/gettext'
  depends_on 'staticfloat/juliadeps/libffi'

  fails_with :llvm do
    build 2334
    cause "Undefined symbol errors while linking"
  end

  resource 'config.h.ed' do
    url 'https://trac.macports.org/export/111532/trunk/dports/devel/glib2/files/config.h.ed'
    version '111532'
    sha1 '0926f19d62769dfd3ff91a80ade5eff2c668ec54'
  end if build.universal?

  def patches
    p = {}
    p[:p1] = []
    # https://bugzilla.gnome.org/show_bug.cgi?id=673135 Resolved as wontfix,
    # but needed to fix an assumption about the location of the d-bus machine
    # id file.
    p[:p1] << "https://gist.github.com/jacknagel/6700436/raw/a94f21a9c5ccd10afa0a61b11455c880640f3133/glib-configurable-paths.patch"
    # Fixes compilation with FSF GCC. Doesn't fix it on every platform, due
    # to unrelated issues in GCC, but improves the situation.
    # Patch submitted upstream: https://bugzilla.gnome.org/show_bug.cgi?id=672777
    p[:p1] << "https://gist.github.com/mistydemeo/8c7eaf0940b6b9159779/raw/11b3b1f09d15ccf805b0914a15eece11685ea8a5/gio.diff"
    p[:p0] = "https://trac.macports.org/export/111532/trunk/dports/devel/glib2/files/patch-configure.diff" if build.universal?
    p
  end

  def install
    ENV.universal_binary if build.universal?

    # -w is said to causes gcc to emit spurious errors for this package
    ENV.enable_warnings if ENV.compiler == :gcc

    # Disable dtrace; see https://trac.macports.org/ticket/30413
    args = %W[
      --disable-maintainer-mode
      --disable-dependency-tracking
      --disable-silent-rules
      --disable-dtrace
      --disable-libelf
      --prefix=#{prefix}
      --localstatedir=#{var}
      --with-gio-module-dir=#{HOMEBREW_PREFIX}/lib/gio/modules
    ]

    system "./configure", *args

    if build.universal?
      buildpath.install resource('config.h.ed')
      system "ed -s - config.h <config.h.ed"
    end

    system "make"
    # the spawn-multithreaded tests require more open files
    system "ulimit -n 1024; make check" if build.include? 'test'
    system "make install"

    # This sucks; gettext is Keg only to prevent conflicts with the wider
    # system, but pkg-config or glib is not smart enough to have determined
    # that libintl.dylib isn't in the DYLIB_PATH so we have to add it
    # manually.
    gettext = Formula.factory('gettext').opt_prefix
    inreplace lib+'pkgconfig/glib-2.0.pc' do |s|
      s.gsub! 'Libs: -L${libdir} -lglib-2.0 -lintl',
              "Libs: -L${libdir} -lglib-2.0 -L#{gettext}/lib -lintl"
      s.gsub! 'Cflags: -I${includedir}/glib-2.0 -I${libdir}/glib-2.0/include',
              "Cflags: -I${includedir}/glib-2.0 -I${libdir}/glib-2.0/include -I#{gettext}/include"
    end

    (share+'gtk-doc').rmtree
  end

  test do
    (testpath/'test.c').write <<-EOS.undent
      #include <string.h>
      #include <glib.h>

      int main(void)
      {
          gchar *result_1, *result_2;
          char *str = "string";

          result_1 = g_convert(str, strlen(str), "ASCII", "UTF-8", NULL, NULL, NULL);
          result_2 = g_convert(result_1, strlen(result_1), "UTF-8", "ASCII", NULL, NULL, NULL);

          return (strcmp(str, result_2) == 0) ? 0 : 1;
      }
      EOS
    flags = `pkg-config --cflags --libs glib-2.0`.split + ENV.cflags.split
    system ENV.cc, "-o", "test", "test.c", *flags
    system "./test"
  end
end
