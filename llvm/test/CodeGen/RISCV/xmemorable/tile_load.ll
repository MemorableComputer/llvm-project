; RUN: llc -mtriple=riscv64 -mattr=+xmemorable,+zve32f,+zvl512b -stop-after=finalize-isel %s -o - | FileCheck %s

define <vscale x 8 x float> @good(ptr addrspace(1) %row) {
  %v = load <vscale x 8 x float>, ptr addrspace(1) %row, align 64
  ret <vscale x 8 x float> %v
}
; CHECK-LABEL: name: good
; CHECK: XMV_TILE_LOAD
; CHECK-SAME: :: (load
; CHECK-SAME: addrspace 1)

define <vscale x 8 x float> @bad(ptr %row) {
  %v = load <vscale x 8 x float>, ptr %row, align 64
  ret <vscale x 8 x float> %v
}
; CHECK-LABEL: name: bad
; CHECK-NOT: XMV_TILE_LOAD
