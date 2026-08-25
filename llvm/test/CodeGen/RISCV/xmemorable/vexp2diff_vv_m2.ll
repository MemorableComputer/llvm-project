; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define <vscale x 4 x float> @f(<vscale x 4 x float> %va, <vscale x 4 x float> %vb) {
  %r = call <vscale x 4 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv4f32.i64(<vscale x 4 x float> %va, <vscale x 4 x float> %vb, i64 32)
  ret <vscale x 4 x float> %r
}
declare <vscale x 4 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv4f32.i64(<vscale x 4 x float>, <vscale x 4 x float>, i64)

; CHECK: {{vsetivli|vsetvli}} {{.*}}e32, m2,
; CHECK: vexp2diff.vv
