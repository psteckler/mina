{ inputs, static ? false, ... }@args:
let
  opam-nix = inputs.opam-nix.lib.${pkgs.system};

  pkgs = if static then args.pkgs.pkgsMusl else args.pkgs;

  inherit (builtins) filterSource path;

  inherit (pkgs.lib) hasPrefix;

  external-repo =
    opam-nix.makeOpamRepoRec ../src/external; # Pin external packages
  repos = [ external-repo inputs.opam-repository ];

  export =
    opam-nix.opamListToQuery (opam-nix.importOpam ../src/opam.export).installed;
  external-packages = pkgs.lib.getAttrs [
    "sodium"
    "capnp"
    "rpc_parallel"
    "ocaml-extlib"
    "async_kernel"
    "base58"
    "graphql_ppx"
    "ppx_deriving_yojson"
  ] (builtins.mapAttrs (_: pkgs.lib.last) (opam-nix.listRepo external-repo));

  implicit-deps = export // external-packages;

  scope = opam-nix.applyOverlays opam-nix.__overlays
    (opam-nix.defsToScope pkgs (opam-nix.queryToDefs repos implicit-deps));

  installedPackageNames =
    map (x: (opam-nix.splitNameVer x).name) (builtins.attrNames implicit-deps);

  sourceInfo = inputs.self.sourceInfo or { };
  dds = x: x.overrideAttrs (o: { dontDisableStatic = true; });

  external-libs = with pkgs;
    if static then
      map dds [
        (zlib.override { splitStaticOutput = false; })
        (bzip2.override { linkStatic = true; })
        (jemalloc)
        (gmp.override { withStatic = true; })
        (openssl.override { static = true; })
        libffi
      ]
    else [
      zlib
      bzip2
      jemalloc
      gmp
      openssl
      libffi
    ];

  filtered-src = with inputs.nix-filter.lib;
    filter {
      root = ../.;
      include = [ "src" "dune" "dune-project" "./graphql_schema.json" ];
    };

  dockerfiles-scripts = path {
    path = filterSource (name: type:
    hasPrefix (toString (../. + "/dockerfiles")) name) ../.;
  };

  overlay = self: super:
    let
      ocaml-libs =
        builtins.attrValues (pkgs.lib.getAttrs installedPackageNames self);
    in {
      sodium = super.sodium.overrideAttrs (_: {
        NIX_CFLAGS_COMPILE = "-I${pkgs.sodium-static.dev}/include";
        propagatedBuildInputs = [ pkgs.sodium-static ];
        preBuild = ''
          export LD_LIBRARY_PATH="${super.ctypes}/lib/ocaml/${super.ocaml.version}/site-lib/ctypes";
        '';
      });

      rpc_parallel = super.rpc_parallel.overrideAttrs
        (oa: { buildInputs = oa.buildInputs ++ [ self.ctypes ]; });

      mina = pkgs.stdenv.mkDerivation ({
        pname = "mina";
        version = "dev";
        # Prevent unnecessary rebuilds on non-source changes
        src = filtered-src;

        # TODO, get this from somewhere
        MARLIN_REPO_SHA = "<unknown>";
        MINA_COMMIT_DATE =
          if sourceInfo ? rev then sourceInfo.lastModifiedDate else "<unknown>";
        MINA_COMMIT_SHA1 = sourceInfo.rev or "DIRTY";
        MINA_BRANCH = "<unknown>";

        buildInputs = ocaml-libs ++ external-libs;
        nativeBuildInputs =
          [ self.dune self.ocamlfind pkgs.capnproto pkgs.removeReferencesTo ]
          ++ ocaml-libs;

        # todo: slimmed rocksdb
        MINA_ROCKSDB = "${pkgs.rocksdb}/lib/librocksdb.a";
        GO_CAPNP_STD = "${pkgs.go-capnproto2.src}/std";

        MARLIN_PLONK_STUBS = "${pkgs.marlin_plonk_bindings_stubs}/lib";
        configurePhase = ''
          export MINA_ROOT="$PWD"
          patchShebangs .
        '';

        buildPhase = ''
          dune build --display=short src/app/logproc/logproc.exe src/app/cli/src/mina.exe src/app/cli/src/mina_testnet_signatures.exe src/app/cli/src/mina_mainnet_signatures.exe src/app/rosetta/rosetta.exe src/app/rosetta/rosetta_testnet_signatures.exe src/app/rosetta/rosetta_mainnet_signatures.exe -j$NIX_BUILD_CORES
          dune exec src/app/runtime_genesis_ledger/runtime_genesis_ledger.exe -- --genesis-dir _build/coda_cache_dir
        '';

        outputs = [ "out" "mainnet" "testnet" "genesis" ];

        installPhase = ''
          mkdir -p $out/bin $mainnet/bin $testnet/bin $genesis/bin $genesis/var/lib/coda
          mv _build/default/src/app/cli/src/mina.exe $out/bin/mina
          mv _build/default/src/app/logproc/logproc.exe $out/bin/logproc
          mv _build/default/src/app/rosetta/rosetta.exe $out/bin/rosetta
          mv _build/default/src/app/runtime_genesis_ledger/runtime_genesis_ledger.exe $genesis/bin/runtime_genesis_ledger
          mv _build/default/src/app/cli/src/mina_mainnet_signatures.exe $mainnet/bin/mina_mainnet_signatures
          mv _build/default/src/app/rosetta/rosetta_mainnet_signatures.exe $mainnet/bin/rosetta_mainnet_signatures
          mv _build/default/src/app/cli/src/mina_testnet_signatures.exe $testnet/bin/mina_testnet_signatures
          mv _build/default/src/app/rosetta/rosetta_testnet_signatures.exe $testnet/bin/rosetta_testnet_signatures
          mv _build/coda_cache_dir/genesis* $genesis/var/lib/coda
          remove-references-to -t $(dirname $(dirname $(command -v ocaml))) {$out/bin/*,$mainnet/bin/*,$testnet/bin*,$genesis/bin/*}
        '';
      } // pkgs.lib.optionalAttrs static { OCAMLPARAM = "_,ccopt=-static"; }
        // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
          OCAMLPARAM = "_,cclib=-lc++";
        });

      mina_tests = self.mina.overrideAttrs (oa: {
        pname = "mina_tests";
        src = filtered-src;
        outputs = [ "out" ];
        MINA_LIBP2P_HELPER_PATH = "${pkgs.libp2p_helper}/bin/libp2p_helper";
        TZDIR = "${pkgs.tzdata}/share/zoneinfo";
        nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.ephemeralpg ];
        buildPhase = ''
          dune build graphql_schema.json --display=short
          export MINA_TEST_POSTGRES="$(pg_tmp -w 1200)"
          psql "$MINA_TEST_POSTGRES" < src/app/archive/create_schema.sql
          dune runtest src/app src/lib --display=short
        '';
        installPhase = "touch $out";
      });

      mina_client_sdk = pkgs.stdenv.mkDerivation {
        pname = "mina_client_sdk";
        version = "dev";
        src = filtered-src;

        buildInputs = ocaml-libs;

        buildPhase = ''
          export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$opam__zarith__lib/zarith"
          dune build --display=short src/app/client_sdk/client_sdk.bc.js --profile=nonconsensus_mainnet
        '';

        installPhase = ''
          mkdir -p $out/share/client_sdk
          mv _build/default/src/app/client_sdk/client_sdk.bc.js $out/share/client_sdk
        '';
      };

      mina_build_config = pkgs.stdenv.mkDerivation {
        pname = "mina_build_config";
        version = "dev";
        src = filtered-src;
        nativeBuildInputs = [ pkgs.rsync ];

        installPhase = ''
          mkdir -p $out/etc/coda/build_config
          cp src/config/mainnet.mlh $out/etc/coda/build_config/BUILD.mlh
          rsync -Huav src/config/* $out/etc/coda/build_config/.
        '';
      };

      mina_daemon_scripts = pkgs.stdenv.mkDerivation {
        pname = "mina_daemon_scripts";
        version = "dev";
        src = dockerfiles-scripts;
        buildInputs = [ pkgs.bash pkgs.python3 ];
        installPhase = ''
          mkdir -p $out/healthcheck $out/entrypoint.d
          mv dockerfiles/scripts/healthcheck-utilities.sh $out/healthcheck/utilities.sh
          mv dockerfiles/scripts/cron_job_dump_ledger.sh $out/cron_job_dump_ledger.sh
          mv dockerfiles/scripts/daemon-entrypoint.sh $out/entrypoint.sh
          mv dockerfiles/puppeteer-context/* $out/
        '';
      };
    };
in scope.overrideScope' overlay
