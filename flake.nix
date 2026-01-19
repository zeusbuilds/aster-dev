{
  description = "Aster - Bitcoin & Layer 2 Wallet Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/ffcdcf99d65c61956d882df249a9be53e5902ea5";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        flutter = pkgs.flutter;

        androidComposition = pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "11.0";
          platformToolsVersion = "34.0.5";
          buildToolsVersions = [ "34.0.0" ];
          platformVersions = [ "34" "33" "32" ];
          includeEmulator = false;
          includeSystemImages = false;
          includeSources = false;
        };
        androidSdk = androidComposition.androidsdk;

        jdk = pkgs.jdk21;
        cocoapods = pkgs.cocoapods;

        commonBuildInputs = with pkgs; [
          flutter
          dart
          jdk
          androidSdk
          git
          curl
          unzip
          which
        ];

        macosBuildInputs = with pkgs; lib.optionals (system == "aarch64-darwin" || system == "x86_64-darwin") [
          cocoapods
        ];

        buildInputs = commonBuildInputs ++ macosBuildInputs;

        envVars = ''
          export ANDROID_HOME="${androidSdk}/libexec/android-sdk"
          export ANDROID_SDK_ROOT="$ANDROID_HOME"
          export JAVA_HOME="${jdk}"
          export PATH="$JAVA_HOME/bin:$PATH"
          export PATH="$ANDROID_HOME/platform-tools:$PATH"
          export PATH="$ANDROID_HOME/build-tools/34.0.0:$PATH"
          export PATH="$ANDROID_HOME/tools:$PATH"
          export PATH="$ANDROID_HOME/tools/bin:$PATH"
          export PATH="${flutter}/bin:$PATH"
          
          ${pkgs.lib.optionalString (system == "aarch64-darwin" || system == "x86_64-darwin") ''
            export PATH="${cocoapods}/bin:$PATH"
          ''}
          
          fix_build_permissions() {
            if [ -d "build" ]; then
              echo "Fixing build directory permissions..."
              find build -type d -exec chmod u+w {} + 2>/dev/null || true
              find build -type f -exec chmod u+w {} + 2>/dev/null || true
              for fw in build/ios/*/Flutter.framework; do
                if [ -d "$fw" ]; then
                  chmod -R u+w "$fw" 2>/dev/null || true
                fi
              done
              echo "✓ Fixed build directory permissions"
            else
              echo "No build directory found"
            fi
          }
          
          flutter() {
            local needs_fix=false
            for arg in "$@"; do
              if [ "$arg" = "run" ] || [ "$arg" = "build" ] || [ "$arg" = "assemble" ]; then
                needs_fix=true
                break
              fi
            done
            
            if [ "$needs_fix" = "true" ]; then
              (
                while [ -d "build" ]; do
                  if [ -d "build/ios" ]; then
                    find build/ios -type d -exec chmod u+w {} + 2>/dev/null || true
                    find build/ios -type f -exec chmod u+w {} + 2>/dev/null || true
                    for fw in build/ios/*/Flutter.framework; do
                      if [ -d "$fw" ]; then
                        chmod -R u+w "$fw" 2>/dev/null || true
                      fi
                    done
                  fi
                  sleep 0.05
                done
              ) &
              local watcher_pid=$!
              
              if [ -d "build" ]; then
                find build -type d -exec chmod u+w {} + 2>/dev/null || true
                find build -type f -exec chmod u+w {} + 2>/dev/null || true
              fi
              
              command flutter "$@"
              local exit_code=$?
              
              kill $watcher_pid 2>/dev/null || true
              wait $watcher_pid 2>/dev/null || true
              
              return $exit_code
            else
              command flutter "$@"
            fi
          }
          
          echo "✓ Flutter version: $(flutter --version | head -n 1)"
          echo "✓ Dart version: $(dart --version)"
          echo "✓ Java version: $(java -version 2>&1 | head -n 1)"
          echo ""
          echo "Run 'flutter doctor' to check your setup."
          echo "Run 'make bootstrap' for initial project setup."
        '';
      in
      {
        devShells.default = pkgs.mkShellNoCC {
          buildInputs = buildInputs;

          shellHook = envVars;
        };
      });
}
