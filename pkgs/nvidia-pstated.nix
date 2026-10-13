{
  callPackage,
  cmake,
  cudaPackages,
  lib,
  runCommand,
  stdenv,
}:

let
  inherit (callPackage ./sources.nix { }) nvidiaPstated;

  nvapi = runCommand "nvapi-sdk" { } ''
    mkdir -p $out
    tar xf ${nvidiaPstated.nvapi} --strip-components=1 -C $out
  '';
in
stdenv.mkDerivation {
  pname = "nvidia-pstated";
  version = "0-unstable-${lib.substring 0 7 nvidiaPstated.src.rev}";
  inherit (nvidiaPstated) src;

  nativeBuildInputs = [ cmake ];

  # Link NVML directly: find_package(CUDAToolkit) would require nvcc and pull
  # more unfree CUDA packages than the one header package needed here.
  buildInputs = [
    cudaPackages.cuda_nvml_dev.include
    cudaPackages.cuda_nvml_dev.stubs
  ];
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail 'find_package(CUDAToolkit REQUIRED COMPONENTS nvml)' "" \
      --replace-fail 'CUDA::nvml' 'nvidia-ml'
  '';
  NIX_LDFLAGS = "-L${cudaPackages.cuda_nvml_dev.stubs}/lib/stubs";

  cmakeFlags = [
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_NVAPI" "${nvapi}")
    (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
  ];

  installPhase = "install -Dm755 nvidia-pstated $out/bin/nvidia-pstated";

  meta = {
    description = "Force idle NVIDIA GPUs into a low performance state";
    homepage = "https://github.com/sasha0552/nvidia-pstated";
    license = lib.licenses.gpl3Only;
    mainProgram = "nvidia-pstated";
    platforms = [ "x86_64-linux" ];
  };
}
