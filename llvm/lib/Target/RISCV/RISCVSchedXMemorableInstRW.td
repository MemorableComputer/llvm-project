//===- RISCVSchedXMemorableInstRW.td - custom-op InstRW ----*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Scheduling info for the XMemorable custom ops. Hand-written baseline;
// the sched-td generator (generate_isa.py --sched-td) regenerates this file
// from isa/*.yaml. Included from RISCVSchedXMemorable.td INSIDE
// `let SchedModel = XMemorableModel`.
//
// Annotations target the per-LMUL PSEUDOS (PseudoXMV_<OP>_M<X>) for every
// pseudo-backed op -- their real MC defs never reach the scheduler -- and the
// real defs only for the ops with no pseudo (tile.load/tile.store are m4-only
// with vl architecturally ignored; vappend/store.transposed/cmul/
// matrix.multiply_drain have no vector-register LMUL dimension).
//
// Lane/FU assignment (design spec Sec 2):
//   value ops (vexp2diff.vv/.fx)   -> [XMDispV, XMFuSfu]
//   quantize stores (store.int4.*) -> [XMDispV, XMFuStore]
//   tile.load / vappend            -> [XMDispV, XMFuLoad]  (load FU's path)
//   tile.store / store.transposed  -> [XMDispV, XMFuStore]
//   matrix.multiply_drain          -> [XMDispM, XMFuMatrix]
//   cmul (GPR-only op)             -> [XMDispS]
// Dispatch lane occupancy is exactly 1 cycle (dense vector dispatch is how
// the hand .S kernels bank queue surplus); FU occupancy = beat count (LMUL
// beats for the per-LMUL pseudos, 4 for the m4-only tile ops, 16 for the
// drain). Producer latencies coarse and round per the design (m4 producers
// ~8, drain ~20); tune only if the btb measurement demands it.
//
//===----------------------------------------------------------------------===//

foreach mx = ["M1", "M2", "M4", "M8"] in {
  defvar beats = !cond(!eq(mx, "M1") : 1,
                       !eq(mx, "M2") : 2,
                       !eq(mx, "M4") : 4,
                       !eq(mx, "M8") : 8);

  let Latency = 8, ReleaseAtCycles = [1, beats] in
  def XMWriteVExp2Diff_ # mx : SchedWriteRes<[XMDispV, XMFuSfu]>;
  def : InstRW<[!cast<SchedWriteRes>("XMWriteVExp2Diff_" # mx)],
               (instrs !cast<Instruction>("PseudoXMV_VEXP2DIFF_VV_" # mx),
                       !cast<Instruction>("PseudoXMV_VEXP2DIFF_FX_" # mx))>;

  let Latency = 4, ReleaseAtCycles = [1, beats] in
  def XMWriteVStoreInt4_ # mx : SchedWriteRes<[XMDispV, XMFuStore]>;
  def : InstRW<[!cast<SchedWriteRes>("XMWriteVStoreInt4_" # mx)],
               (instrs !cast<Instruction>("PseudoXMV_STORE_INT4_E8M0_" # mx),
                       !cast<Instruction>("PseudoXMV_STORE_INT4_E4M3_" # mx),
                       !cast<Instruction>("PseudoXMV_STORE_INT4_E8M3_" # mx))>;
}

// tile.load / tile.store: real m4-only defs (no pseudo), 4 beats each.
let Latency = 8, ReleaseAtCycles = [1, 4] in
def XMWriteVTileLoad : SchedWriteRes<[XMDispV, XMFuLoad]>;
def : InstRW<[XMWriteVTileLoad], (instrs XMV_TILE_LOAD)>;

let Latency = 4, ReleaseAtCycles = [1, 4] in
def XMWriteVTileStore : SchedWriteRes<[XMDispV, XMFuStore]>;
def : InstRW<[XMWriteVTileStore], (instrs XMV_TILE_STORE)>;

// vappend appends one row via the load FU's spine (yaml latency 2);
// store.transposed writes one bank row via the store FU (yaml latency 4).
let Latency = 2, ReleaseAtCycles = [1, 1] in
def XMWriteVAppend : SchedWriteRes<[XMDispV, XMFuLoad]>;
def : InstRW<[XMWriteVAppend], (instrs XMV_VAPPEND)>;

let Latency = 4, ReleaseAtCycles = [1, 1] in
def XMWriteVStoreTransposed : SchedWriteRes<[XMDispV, XMFuStore]>;
def : InstRW<[XMWriteVStoreTransposed], (instrs XMV_STORE_TRANSPOSED)>;

// matrix.multiply_drain: matrix lane, 16 beats (accumulator depth) through
// the matrix FU, drain results land ~20 cycles out.
let Latency = 20, ReleaseAtCycles = [1, 16] in
def XMWriteMatrixMultiplyDrain : SchedWriteRes<[XMDispM, XMFuMatrix]>;
def : InstRW<[XMWriteMatrixMultiplyDrain], (instrs XMV_MATRIX_MULTIPLY_DRAIN)>;

// cmul: scalar-lane GPR-to-GPR op.
let Latency = 2 in
def XMWriteCMul : SchedWriteRes<[XMDispS]>;
def : InstRW<[XMWriteCMul], (instrs XMV_CMUL)>;
