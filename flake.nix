# Run the container with the following command
# The bind-mount is for testing the modification scripts
# After nom build, run "docker load -i result" to load the symlinked image into
# docker

# Run the container with:
# docker run -it --network host --privileged -v $(pwd):/root/test revpi-bookworm-docker
{
  inputs.nixpkgs = {
    url = "github:NixOS/nixpkgs/nixos-unstable"; # Example branch for Linux
  };
  inputs.utils.url = "github:numtide/flake-utils";

  outputs = {self, nixpkgs, utils}:
    let
      forAllSystems = utils.lib.eachDefaultSystem;
      supportedRPIImages = {
        bookworm = {
          url = "https://revolutionpi.com/fileadmin/downloads/images/250528-revpi-bookworm-arm64-default.zip";
          hash = "sha256-0Eyax37kcTG9i0t93/uF+NiFNjZfJTO+P6IuTCRD0+g=";
        };
      };
    in 
      forAllSystems (system:
        let
          # Import our packages
          pkgs = import nixpkgs {inherit system;};

          imageBakery = pkgs.stdenv.mkDerivation {
            name = "imagebakery";
            # Fetch our fork of the RPI image bakery, as we have
            # modified it to work with Nix and with Containers
            src = pkgs.fetchFromGitHub {
              owner = "aomahony-saronic";
              repo = "imagebakery";
              rev = "291a0140d5bfbc8e0f633f40ca51e2d5255be82a";
              hash = "sha256-NwUKU3Fx9jV4V/Cs9bk54GfSg3UOVJrDWCO5QfPcUCw=";
            };
            buildPhase = '''';
            installPhase = ''
              cp -R . $out
            '';
          };

          imageDerivations = pkgs.lib.attrsets.mapAttrs (name: value: 
            let
              requiredPackages = [
                 pkgs.bash
                 pkgs.coreutils
                 pkgs.which
                 pkgs.lsof
                 pkgs.dosfstools
                 pkgs.util-linux
                 pkgs.parted
                 pkgs.curl
                 pkgs.file
                 pkgs.multipath-tools
                 pkgs.git
                 pkgs.iputils
                 pkgs.gnupatch
                 pkgs.wget
                 pkgs.lsb-release
                 pkgs.tree
              ];
              # Fetch our raw RPI image
              rpiImage = pkgs.stdenv.mkDerivation {
                name = "revpios-${name}-container-image";
                src = pkgs.fetchurl {
                  url = value.url;
                  sha256 = value.hash;
                };

                unpackPhase = ''
                  unzip $src -d .
                '';

                nativeBuildInputs = [ 
                     pkgs.unzip
                ];

                buildPhase = ''
                '';

                installPhase = ''
                  mkdir -p $out
                  # Copy our extracted image to the $out directory
                  cp *.img $out
                '';
              };
            in
              pkgs.dockerTools.buildImage {
                name = "revpi-${name}-docker";
                tag = "latest";
                
                # The Ubuntu image seems to be the only one that works
                # with losetup.  No idea why, as it works on my own Nix image
                fromImage = pkgs.dockerTools.pullImage {
                  imageName = "ubuntu";
                  imageDigest = "sha256:440dcf6a5640b2ae5c77724e68787a906afb8ddee98bf86db94eea8528c2c076";
                  sha256 = "sha256-EsKRAlEhJByqGObyGS1BZ3xGOWn9039ejSbVzKRVedw=";
                };
                
                # This really sucks: the only way to get files into the container image
                # from what I see is to copy them over with this method, which builds a symlinked
                # env and copies the file paths over directly into the container, but into the root
                # directory instead of elsewhere.  I tried a few other means, but nothing worked
                # to include the imageBakery and rpiImage for now, so whatever
                copyToRoot = pkgs.buildEnv {
                  name = "revpi-${name}-docker-env";
                  paths = requiredPackages ++ [
                    imageBakery
                    rpiImage
                  ];
                };

                config = {
                  Cmd = [ "${pkgs.bash}/bin/bash" ];
                  WorkingDir = "/";
                  Env = [
                    # Our required packages need to be on the $PATH
                    "PATH=${pkgs.lib.makeBinPath requiredPackages}:/usr/bin:/usr/sbin:/bin"
                  ];
                };
              }
          ) supportedRPIImages;
        in 
          {
            packages = imageDerivations;
          }
      );
}
