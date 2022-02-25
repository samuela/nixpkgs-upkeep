final: prev: {
  cudatoolkit = prev.cudatoolkit_11_5;
  cudnn = prev.cudnn_8_3_cudatoolkit_11_5;
  blas = prev.blas.override { blasProvider = final.mkl; };
  lapack = prev.lapack.override { lapackProvider = final.mkl; };
}
