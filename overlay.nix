final: prev: {
  # See https://discourse.nixos.org/t/getting-different-results-for-the-same-build-on-two-equally-configured-machines/17921
  # as to why I don't use MKL by default anymore.
  # blas = prev.blas.override { blasProvider = final.mkl; };
  # lapack = prev.lapack.override { lapackProvider = final.mkl; };
}
