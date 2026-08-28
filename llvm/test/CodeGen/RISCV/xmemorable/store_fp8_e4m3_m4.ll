; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -O2 %s -o - | FileCheck %s

define void @f(<vscale x 8 x float> %v, ptr %data, ptr %scale) {
  call void @llvm.riscv.memorable.fp8.quantize.e4m3.nxv8f32.i64(<vscale x 8 x float> %v, ptr %data, ptr %scale, i64 64)
  ret void
}
declare void @llvm.riscv.memorable.fp8.quantize.e4m3.nxv8f32.i64(<vscale x 8 x float>, ptr, ptr, i64)

; CHECK: {{vsetivli|vsetvli}} {{.*}}e32, m4,
; CHECK: store.fp8.e4m3
