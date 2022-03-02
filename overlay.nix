final: prev: {
  # There does exist cudatoolkit_11_6, but it does not have a corresponding
  # cudnn version at the moment. See https://github.com/NixOS/nixpkgs/pull/158114.
  cudatoolkit = prev.cudatoolkit_11_5;
  cudnn = prev.cudnn_8_3_cudatoolkit_11_5;
  # See https://discourse.nixos.org/t/getting-different-results-for-the-same-build-on-two-equally-configured-machines/17921
  # as to why I don't use MKL by default anymore.
  # blas = prev.blas.override { blasProvider = final.mkl; };
  # lapack = prev.lapack.override { lapackProvider = final.mkl; };
}
