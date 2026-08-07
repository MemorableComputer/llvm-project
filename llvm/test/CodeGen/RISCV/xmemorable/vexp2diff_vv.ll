; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define <vscale x 2 x float> @f(<vscale x 2 x float> %vs1, <vscale x 2 x float> %vs2) {
  %r = call <vscale x 2 x float> @llvm.riscv.memorable.vexp2diff.vv(<vscale x 2 x float> %vs1, <vscale x 2 x float> %vs2)
  ret <vscale x 2 x float> %r
}
declare <vscale x 2 x float> @llvm.riscv.memorable.vexp2diff.vv(<vscale x 2 x float>, <vscale x 2 x float>)

; CHECK: vexp2diff.vv
