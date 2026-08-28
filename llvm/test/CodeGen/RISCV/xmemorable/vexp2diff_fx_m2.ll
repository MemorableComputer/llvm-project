; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define <vscale x 4 x i32> @f(<vscale x 4 x float> %va, <vscale x 4 x float> %vb) {
  %r = call <vscale x 4 x i32> @llvm.riscv.memorable.vexp2diff.fx.nxv4i32.nxv4f32.i64(<vscale x 4 x float> %va, <vscale x 4 x float> %vb, i64 32)
  ret <vscale x 4 x i32> %r
}
declare <vscale x 4 x i32> @llvm.riscv.memorable.vexp2diff.fx.nxv4i32.nxv4f32.i64(<vscale x 4 x float>, <vscale x 4 x float>, i64)

; CHECK: {{vsetivli|vsetvli}} {{.*}}e32, m2,
; CHECK: vexp2diff.fx
