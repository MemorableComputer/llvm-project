; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define void @f(<vscale x 4 x float> %v, ptr %data, ptr %scale) {
  call void @llvm.riscv.memorable.int4.quantize.e8m0.nxv4f32.i64(<vscale x 4 x float> %v, ptr %data, ptr %scale, i64 32)
  ret void
}
declare void @llvm.riscv.memorable.int4.quantize.e8m0.nxv4f32.i64(<vscale x 4 x float>, ptr, ptr, i64)

; CHECK: {{vsetivli|vsetvli}} {{.*}}e32, m2,
; CHECK: store.int4.e8m0
