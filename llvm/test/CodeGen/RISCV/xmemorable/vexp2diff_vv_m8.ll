; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define <vscale x 16 x float> @f(<vscale x 16 x float> %va, <vscale x 16 x float> %vb) {
  %r = call <vscale x 16 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv16f32.i64(<vscale x 16 x float> %va, <vscale x 16 x float> %vb, i64 128)
  ret <vscale x 16 x float> %r
}
declare <vscale x 16 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv16f32.i64(<vscale x 16 x float>, <vscale x 16 x float>, i64)

; CHECK: {{vsetivli|vsetvli}} {{.*}}e32, m8,
; CHECK: vexp2diff.vv
