{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  makeBinaryWrapper,
  git,
  python3,
  runCommand,
  nix-update-script,
}:

let
  libc = stdenv.cc.libc;

  # The blessed packages' Goose sources at the refs src/blessed.txt names,
  # keyed by where a fetch puts them under GOOSE_HOME/pkg. The tests of the
  # audio, gfx, physics and ui modules parse and typecheck against them;
  # their native layers are not built. Pinned by commit, since upstream moves
  # the v1 tags.
  blessedPackages = {
    "github.com/aardappel/goose_gfx/v1" = fetchFromGitHub {
      owner = "aardappel";
      repo = "goose_gfx";
      rev = "6cfa3dec2ef2a6cb19ee71548b38151094e947bd";
      hash = "sha256-Sv04fpyQZ1VDV7ozSaYyUS0GZVjgUJPQ74NIGdlEDB0=";
    };
    "github.com/aardappel/goose_physics/v1" = fetchFromGitHub {
      owner = "aardappel";
      repo = "goose_physics";
      rev = "8eec2739fc75016c2e19ff633e668d20260c4e1a";
      hash = "sha256-3aEF94PiboxSq0jPbnopS0Dtv0XaabDqsQlctcpQW2s=";
    };
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "goose-compiler";
  version = "2026.3";

  src = fetchFromGitHub {
    owner = "aardappel";
    repo = "goose";
    tag = "v${finalAttrs.version}";
    hash = "sha256-tEPwgeJ3rQ5K1ePl06hksZFiZhbUYHbWib6FFt9Rgj4=";
  };

  patches = [
    # Adds GOOSE_TCC_LIB_PATH and GOOSE_TCC_{SYSINCLUDEPATHS,LIBPATHS,CRTPREFIX}
    # cache variables, so the binary names its installed TinyCC runtime rather
    # than the build directory, and the in-process backend finds a C library
    # outside /usr. Not yet upstream.
    ./tcc-paths.patch
  ];

  nativeBuildInputs = [
    cmake
    ninja
    makeBinaryWrapper
  ];

  # The blessed packages (gfx, audio, ui, physics) stay out: compiling them in
  # fetches their repositories at configure time. A program importing one
  # builds it into GOOSE_HOME on first use, with the git, cmake and C compiler
  # the wrapper provides.
  cmakeFlags = [
    (lib.cmakeFeature "GOOSE_BUILTIN_LIBS" "")
    (lib.cmakeFeature "GOOSE_TCC_LIB_PATH" "${placeholder "out"}/libexec/goose/tcclib")
  ]
  # TinyCC's defaults look under /usr; macOS needs no override, since the
  # upstream CMake already points TinyCC at the SDK the build uses.
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    (lib.cmakeFeature "GOOSE_TCC_SYSINCLUDEPATHS" "{B}/include:${lib.getDev libc}/include")
    (lib.cmakeFeature "GOOSE_TCC_LIBPATHS" "{B}:${lib.getLib libc}/lib")
    (lib.cmakeFeature "GOOSE_TCC_CRTPREFIX" "${lib.getLib libc}/lib")
  ];

  # The compiler finds stdlib/ and tcclib/ beside its resolved executable, the
  # layout of an upstream release (scripts/package_release.py).
  installPhase = ''
    runHook preInstall

    install -Dm755 goose -t $out/libexec/goose
    cp -r tcclib ../stdlib $out/libexec/goose/

    # Appended, so a C compiler, git or cmake the user puts on PATH wins.
    makeWrapper $out/libexec/goose/goose $out/bin/goose \
      --suffix PATH : ${
        lib.makeBinPath [
          stdenv.cc
          git
          cmake
        ]
      }

    install -Dm644 ../README.md ../docs/*.md -t $out/share/doc/goose

    runHook postInstall
  '';

  # Upstream's full suite, against the installed compiler: generated C at -O0
  # and -O2, the JIT, the error fixtures, the bootstrap and the samples. It
  # runs the unwrapped binary, since one check copies the executable away
  # from its stdlib/ and expects it to find none; passthru.tests covers the
  # wrapper.
  doInstallCheck = true;
  nativeInstallCheckInputs = [
    python3
    git
  ];
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME=$(mktemp -d)
    # The runner sets GOOSE_HOME to build/goose-home, this directory.
    ${lib.concatStrings (
      lib.mapAttrsToList (key: src: ''
        mkdir -p goose-home/pkg/${dirOf key}
        cp -r --no-preserve=mode ${src} goose-home/pkg/${key}
      '') blessedPackages
    )}
    python3 ../test/run_tests.py --exe $out/libexec/goose/goose -j $NIX_BUILD_CORES

    runHook postInstallCheck
  '';

  passthru = {
    tests.hello =
      runCommand "goose-compiler-test-hello"
        {
          nativeBuildInputs = [ finalAttrs.finalPackage ];
        }
        ''
          export HOME=$(mktemp -d)
          cat > hello.goose <<'EOF'
          fn main() {
              print("hello from goose");
          }
          EOF

          # In-process, through TinyCC, then natively through the wrapped cc.
          [ "$(goose hello.goose)" = "hello from goose" ]
          goose build hello.goose
          [ "$(./hello)" = "hello from goose" ]
          touch $out
        '';

    updateScript = nix-update-script { };
  };

  meta = {
    description = "Memory-safe systems language with no heap allocator, garbage collector or lifetime annotations";
    longDescription = ''
      Goose is a systems language that keeps every dynamic value inline on
      compiler-managed data stacks, so memory is freed when its scope ends.
      It compiles to a single C file, runs programs in-process through a
      bundled TinyCC, and ships a language server (`goose lsp`).
    '';
    homepage = "https://github.com/aardappel/goose";
    changelog = "https://github.com/aardappel/goose/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      asl20
      # Vendored TinyCC, linked into the compiler.
      lgpl21Only
      # Vendored cute_spirv (zlib or public domain) and subprocess.h.
      zlib
      unlicense
    ];
    maintainers = [ ];
    mainProgram = "goose";
    # cmake/libtcc.cmake has TinyCC backends for x86-64 and arm64 only.
    platforms = lib.intersectLists (lib.platforms.x86_64 ++ lib.platforms.aarch64) (
      lib.platforms.linux ++ lib.platforms.darwin
    );
  };
})
