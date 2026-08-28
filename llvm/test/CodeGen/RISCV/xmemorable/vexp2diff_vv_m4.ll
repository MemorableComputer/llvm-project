; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define <vscale x 8 x float> @f(<vscale x 8 x float> %va, <vscale x 8 x float> %vb) {
  %r = call <vscale x 8 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv8f32.i64(<vscale x 8 x float> %va, <vscale x 8 x float> %vb, i64 64)
  ret <vscale x 8 x float> %r
}
declare <vscale x 8 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv8f32.i64(<vscale x 8 x float>, <vscale x 8 x float>, i64)

; CHECK: {{vsetivli|vsetvli}} {{.*}}e32, m4,
; CHECK: vexp2diff.vv
