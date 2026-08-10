; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -stop-after=finalize-isel %s -o - | FileCheck %s

define void @good(<vscale x 8 x float> %v, ptr addrspace(1) %row) {
  store <vscale x 8 x float> %v, ptr addrspace(1) %row, align 64
  ret void
}
; CHECK-LABEL: name: good
; CHECK: XMV_TILE_STORE
; CHECK-SAME: :: (store
; CHECK-SAME: addrspace 1)

define void @bad(<vscale x 8 x float> %v, ptr %row) {
  store <vscale x 8 x float> %v, ptr %row, align 64
  ret void
}
; CHECK-LABEL: name: bad
; CHECK-NOT: XMV_TILE_STORE
