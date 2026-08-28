//===- IntrinsicsRISCVXMemorable.td - Xmemorable intrinsics -----*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file defines all of the Memorable decode-engine vendor (Xmemorable)
// intrinsics for RISC-V.
//
//===----------------------------------------------------------------------===//

let TargetPrefix = "riscv" in {
  // LMUL-polymorphic (framework) intrinsic shapes -- anyvector + VL, the
  // upstream RVV convention (cf. IntrinsicsRISCVXTHead.td); RISCVVIntrinsic
  // wires VLOperand into the backend's intrinsic-info table. No masked
  // forms: this machine has no mask support (isa/vector.yaml).
  class XMVBinaryVVUnMasked
      : DefaultAttrsIntrinsic<[llvm_anyvector_ty],
                              [LLVMMatchType<0>, LLVMMatchType<0>,
                               llvm_anyint_ty],
                              [IntrNoMem]>,
        RISCVVIntrinsic {
    let VLOperand = 2;
  }
  // f32 operands, same-LMUL i32 result (vexp2diff.fx's Q16.16 lanes --
  // isa/vector.yaml's result_type override, generalized per LMUL).
  class XMVBinaryVVFxUnMasked
      : DefaultAttrsIntrinsic<[llvm_anyvector_ty],
                              [llvm_anyvector_ty, LLVMMatchType<1>,
                               llvm_anyint_ty],
                              [IntrNoMem]>,
        RISCVVIntrinsic {
    let VLOperand = 2;
  }
  // Grouped quantize-store: void (value, data, scale, vl) -- vl/16
  // adjacent micro-blocks have no single-i64-store/MMO model, so the
  // data-bank pointer is an ordinary argument and the old m1-only fused
  // (IntrNoMem value + addrspace(2) store) contract is retired. Precise
  // memory attrs (machine-pipeliner plan Task 1):
  // memory(argmem: write, inaccessiblemem: write) -- reads only its vreg,
  // writes data-bank bytes through the data ptr (argmem) AND block-scale
  // bytes into the MIRROR scale bank at an address DERIVED from the data
  // address (the scale ptr arg is hardware routing; kernels pass 0), which
  // only inaccessiblemem can carry. The inaccessiblemem:write half is also
  // the DCE anchor: it keeps the call alive even where the data region is
  // a store-only internal global GlobalOpt/DSE could otherwise reason
  // away. Never IntrReadMem/IntrNoMem (write effect = the CSE/DCE wall).
  //
  // SDNPMemOperand (machine-pipeliner ledger, THE FIX step 1): the
  // MI-level carrier for the MachineMemOperand the backend's
  // getTgtMemIntrinsic hook builds for the DATA-bank write. The hook makes
  // the DAG node a MemIntrinsicSDNode, but a PATTERN-selected node only
  // copies that MMO onto the MachineInstr when the source pattern's node
  // advertises this property (DAGISelMatcherGen: RecordMemRefMatcher +
  // NodeHasMemRefs). Without it the store stays an MMO-less unknown store
  // at MI level -- MachineInstr::mayAlias then answers "may alias" against
  // EVERY other memory op and the load-above-store reorder the fix exists
  // for is still illegal. The only SD property in this file: the tbuf/macc
  // state ops deliberately remain MMO-free unknown-memory ops (their
  // footprints are hidden state, not an argument-addressed range).
  class XMVStoreFp4UnMasked
      : DefaultAttrsIntrinsic<[],
                              [llvm_anyvector_ty, llvm_ptr_ty, llvm_ptr_ty,
                               llvm_anyint_ty],
                              [IntrInaccessibleMemOrArgMemOnly, IntrWriteMem],
                              "", [SDNPMemOperand]>,
        RISCVVIntrinsic {
    let VLOperand = 3;
  }

  def int_riscv_memorable_cmul
      : DefaultAttrsIntrinsic<[llvm_i64_ty],
                              [llvm_i64_ty, llvm_i64_ty], [IntrNoMem]>;

  // Hidden-state ops (task 8 / PR #21, precise attrs per the
  // machine-pipeliner plan Task 1): these touch state the IR cannot see
  // (TBUF/MACC). [IntrReadMem] would look right (vappend architecturally
  // only reads memory) and is NOT: readonly + identical args is CSE-able,
  // silently dropping a state mutation. The blanket [IntrHasSideEffects]
  // that used to wall this off was an opaque scheduling BARRIER; each op
  // now carries its true footprint instead:
  //   * tbuf ops (vappend, store.transposed): IntrInaccessibleMemOrArgMemOnly
  //     -> memory(argmem: readwrite, inaccessiblemem: readwrite). The
  //     inaccessiblemem half is the hidden, position-dependent TBUF state
  //     (auto-wrap/tile-swap) and its WRITE effect is the CSE/DCE anchor;
  //     the argmem-readwrite half over-approximates each op's one-way row
  //     access -- sanctioned: this pin's tablegen composes memory effects
  //     by INTERSECTION only, so argmem:read + inaccessiblemem:readwrite
  //     cannot be expressed asymmetrically.
  //   * the macc op (matrix.multiply_drain): NO attrs at all -> the
  //     default conservative memory(readwrite). It has ZERO pointer args
  //     (bank/tile addresses arrive as i64 scalar handles), so any
  //     *MemOnly attr would wrongly EXCLUDE its real bank reads and
  //     tile-row writes; an unknown-memory call keeps every edge while no
  //     longer serializing the whole scheduling DAG.
  def int_riscv_memorable_vappend
      : DefaultAttrsIntrinsic<[], [llvm_ptr_ty],
                              [IntrInaccessibleMemOrArgMemOnly]>;   // reads mem BUT writes TBUF: never IntrReadMem
  def int_riscv_memorable_store_transposed
      : DefaultAttrsIntrinsic<[], [llvm_i64_ty, llvm_ptr_ty],
                              [IntrInaccessibleMemOrArgMemOnly, ImmArg<ArgIndex<0>>]>;

  def int_riscv_memorable_fp4_quantize_e8m0 : XMVStoreFp4UnMasked;
  def int_riscv_memorable_fp4_quantize_e4m3 : XMVStoreFp4UnMasked;
  def int_riscv_memorable_fp4_quantize_e8m3 : XMVStoreFp4UnMasked;
  def int_riscv_memorable_fp8_quantize_e4m3 : XMVStoreFp4UnMasked;
  def int_riscv_memorable_bf16_quantize : XMVStoreFp4UnMasked;

  def int_riscv_memorable_vexp2diff_vv : XMVBinaryVVUnMasked;
  def int_riscv_memorable_vexp2diff_fx : XMVBinaryVVFxUnMasked;

  def int_riscv_memorable_matrix_multiply_drain
      : DefaultAttrsIntrinsic<[], [llvm_i64_ty, llvm_i64_ty, llvm_i64_ty, llvm_i64_ty],
                              []>;   // NO attrs: bare memory(readwrite), see above
} // TargetPrefix = "riscv"
