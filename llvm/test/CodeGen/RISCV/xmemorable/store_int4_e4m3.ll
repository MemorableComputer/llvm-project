; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -stop-after=finalize-isel %s -o - | FileCheck %s

define void @f(<vscale x 2 x float> %v, ptr addrspace(2) %data, ptr %scale) {
  %q = call i64 @llvm.riscv.memorable.int4.quantize.e4m3(<vscale x 2 x float> %v, ptr %scale)
  store i64 %q, ptr addrspace(2) %data, align 8
  ret void
}
declare i64 @llvm.riscv.memorable.int4.quantize.e4m3(<vscale x 2 x float>, ptr)

; CHECK: XMV_STORE_INT4_E4M3
; CHECK-SAME: :: (store
; CHECK-SAME: addrspace 2)
