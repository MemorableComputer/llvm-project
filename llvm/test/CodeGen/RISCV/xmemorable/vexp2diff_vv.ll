; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define <vscale x 2 x float> @f(<vscale x 2 x float> %va, <vscale x 2 x float> %vb) {
  %r = call <vscale x 2 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv2f32.i64(<vscale x 2 x float> %va, <vscale x 2 x float> %vb, i64 16)
  ret <vscale x 2 x float> %r
}
declare <vscale x 2 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv2f32.i64(<vscale x 2 x float>, <vscale x 2 x float>, i64)

; CHECK: {{vsetivli|vsetvli}} {{.*}}e32, m1,
; CHECK: vexp2diff.vv
