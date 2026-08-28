; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define void @f(<vscale x 2 x float> %v, ptr %data, ptr %scale) {
  call void @llvm.riscv.memorable.fp4.quantize.e4m3.nxv2f32.i64(<vscale x 2 x float> %v, ptr %data, ptr %scale, i64 16)
  ret void
}
declare void @llvm.riscv.memorable.fp4.quantize.e4m3.nxv2f32.i64(<vscale x 2 x float>, ptr, ptr, i64)

; CHECK: {{vsetivli|vsetvli}} {{.*}}e32, m1,
; CHECK: store.fp4.e4m3
