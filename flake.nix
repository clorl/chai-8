{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
			pkgs = import nixpkgs {
				inherit system;
				config = {
					# Specifically allow the insecure QuickJS package
					permittedInsecurePackages = [
						"quickjs-2025-09-13-2"
					];
				};
			};

      jai-fhs = pkgs.buildFHSEnv {
        name = "jai-env";
        
        targetPkgs = pkgs: with pkgs; [
          gcc
          binutils
          gnumake
					cmake
          
          libX11
          libXext
          libXcursor
          libXrandr
          libXi
          libXinerama
          libGL
          libGLU
          mesa
          
          zlib
          curl
          alsa-lib
        ];

        multiPkgs = pkgs: with pkgs; [
					libX11
					libXext
					libXcursor
					libXrandr
					libXi
					libXinerama
					libGL
					libGLU
					mesa
					zlib
					alsa-lib
					zlib
        ];

				profile = ''
					export LD_LIBRARY_PATH=/usr/lib:/usr/lib64:/lib/:/lib64/
					alias jai="/home/topy/Projets/jai/jai/bin/jai"
					chmod +x /home/topy/Projets/jai/jai/bin/jai
				'';

        runScript = "bash";
      };
    in
    {
      # This exposes the FHS environment as the default devShell
      devShells.${system}.default = jai-fhs.env;
    };
}
