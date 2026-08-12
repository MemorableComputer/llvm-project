//==- RISCVSchedXMemorable.td - XMemorable Scheduling Defs -*- tablegen -*-==//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//
// Scheduler model for the xmemorable node: an in-order 3-slot dispatch window
// routed into three decoupled lanes (scalar / vector / matrix), at most one
// op per lane per cycle, with 4-deep issue queues behind the vector FUs.
// Cloned from the SpacemitX60 model (the in-order dual-issue RVV skeleton
// closest to this machine) and remapped onto the two-tier lane/FU resources;
// X60 latencies are deliberately kept -- interleaving pressure comes from the
// 1-wide dispatch-lane resources, not from latency tuning.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Helpers

// Maps LMUL string to corresponding value from the Values array
// LMUL values map to array indices as follows:
//   MF8 -> Values[0], MF4 -> Values[1], MF2 -> Values[2], M1 -> Values[3],
//   M2 -> Values[4], M4 -> Values[5], M8 -> Values[6]
// Shorter lists are allowed, e.g., widening instructions don't work on M8
class XMemorableGetLMULValue<list<int> Values, string LMUL> {
  defvar Index = !cond(
    !eq(LMUL, "MF8"): 0,
    !eq(LMUL, "MF4"): 1,
    !eq(LMUL, "MF2"): 2,
    !eq(LMUL, "M1"):  3,
    !eq(LMUL, "M2"):  4,
    !eq(LMUL, "M4"):  5,
    !eq(LMUL, "M8"):  6,
  );

  assert !lt(Index, !size(Values)),
    "Missing LMUL value for '" # LMUL # "'. " #
    "Expected at least " # !add(Index, 1) # " elements, but got " #
    !size(Values) # ".";

  int c = Values[Index];
}

// Returns BaseValue for LMUL values before startLMUL, Value for startLMUL,
// then doubles Value for each subsequent LMUL
// Example: XMemorableConstValueUntilLMULThenDoubleBase<"M1", 2, 4, "M8"> returns:
//   MF8->2, MF4->2, MF2->2, M1->4, M2->8, M4->16, M8->32
// This is useful for modeling scheduling parameters that scale with LMUL.
class XMemorableConstValueUntilLMULThenDoubleBase<string startLMUL, int BaseValue, int Value, string currentLMUL> {
  assert !le(BaseValue, Value), "BaseValue must be less-equal to Value";
  defvar startPos = XMemorableGetLMULValue<[0, 1, 2, 3, 4, 5, 6], startLMUL>.c;
  defvar currentPos = XMemorableGetLMULValue<[0, 1, 2, 3, 4, 5, 6], currentLMUL>.c;

  // Calculate the difference in positions
  defvar posDiff = !sub(currentPos, startPos);

  // Calculate Value * (2^posDiff)
  int c = !cond(
    !eq(posDiff, 0) : Value,
    !eq(posDiff, 1) : !mul(Value, 2),
    !eq(posDiff, 2) : !mul(Value, 4),
    !eq(posDiff, 3) : !mul(Value, 8),
    !eq(posDiff, 4) : !mul(Value, 16),
    !eq(posDiff, 5) : !mul(Value, 32),
    !eq(posDiff, 6) : !mul(Value, 64),
    true : BaseValue
  );
}

// Same as the previous function but BaseValue == Value
class XMemorableConstValueUntilLMULThenDouble<string startLMUL, int Value, string currentLMUL> {
  int c = XMemorableConstValueUntilLMULThenDoubleBase<startLMUL, Value, Value, currentLMUL>.c;
}

// Returns MF8->1, MF4->1, MF2->2, M1->4, M2->8, M4->16, M8->32
class XMemorableConstOneUntilMF4ThenDouble<string mx> {
  int c = XMemorableConstValueUntilLMULThenDouble<"MF4", 1, mx>.c;
}

// Returns MF8->1, MF4->1, MF2->1, M1->2, M2->4, M4->8, M8->16
class XMemorableConstOneUntilMF2ThenDouble<string mx> {
  int c = XMemorableConstValueUntilLMULThenDouble<"MF2", 1, mx>.c;
}

// Returns MF8->1, MF4->1, MF2->1, M1->1, M2->2, M4->4, M8->8
class XMemorableConstOneUntilM1ThenDouble<string mx> {
  int c = XMemorableConstValueUntilLMULThenDouble<"M1", 1, mx>.c;
}

//===----------------------------------------------------------------------===//
// Latency helper classes

// Used for: arithmetic (add/sub/min/max), saturating/averaging, FP add/sub/min/max
class XMemorableGet4458Latency<string mx> {
  int c = XMemorableGetLMULValue<[/*MF8=*/4, /*MF4=*/4, /*MF2=*/4, /*M1=*/4, /*M2=*/4, /*M4=*/5, /*M8=*/8], mx>.c;
}

// Used for: widening operations (no M8)
class XMemorableGet4588Latency<string mx> {
  int c = XMemorableGetLMULValue<[/*MF8=*/4, /*MF4=*/4, /*MF2=*/4, /*M1=*/4, /*M2=*/5, /*M4=*/8], mx>.c;
}

// Used for: mask-producing comparisons, carry ops with mask, FP comparisons
class XMemorableGet461018Latency<string mx> {
  int c = XMemorableGetLMULValue<[/*MF8=*/4, /*MF4=*/4, /*MF2=*/4, /*M1=*/4, /*M2=*/6, /*M4=*/10, /*M8=*/18], mx>.c;
}

// Used for: FP FMA operations, complex FP ops
class XMemorableGet6678Latency<string mx> {
  int c = XMemorableGetLMULValue<[/*MF8=*/6, /*MF4=*/6, /*MF2=*/6, /*M1=*/6, /*M2=*/6, /*M4=*/7, /*M8=*/8], mx>.c;
}

//===----------------------------------------------------------------------===//

class XMemorableIsWorstCaseMX<string mx, list<string> MxList> {
  string LLMUL = LargestLMUL<MxList>.r;
  bit c = !eq(mx, LLMUL);
}

class XMemorableIsWorstCaseMXSEW<string mx, int sew, list<string> MxList, bit isF = 0> {
  string LLMUL = LargestLMUL<MxList>.r;
  int SSEW = SmallestSEW<mx, isF>.r;
  bit c = !and(!eq(mx, LLMUL), !eq(sew, SSEW));
}

// Deliberately the X60 skeleton's value, NOT the machine's real VLEN (the
// xmemorable node is zvl512b): this defvar only feeds the X60-derived
// latency/occupancy helpers below (segmented ld/st scaling), which the
// design keeps as-is -- harmless defaults; the 1-wide lane resources are
// what drive interleaving, not these numbers.
defvar XMemorableVLEN = 256;
defvar XMemorableDLEN = !div(XMemorableVLEN, 2);

class XMemorableGetLMulCycles<string mx> {
  int c = !cond(
    !eq(mx, "M1") : 1,
    !eq(mx, "M2") : 2,
    !eq(mx, "M4") : 4,
    !eq(mx, "M8") : 8,
    !eq(mx, "MF2") : 1,
    !eq(mx, "MF4") : 1,
    !eq(mx, "MF8") : 1
  );
}

class XMemorableGetVLMAX<string mx, int sew> {
  defvar LMUL = XMemorableGetLMulCycles<mx>.c;
  int val = !cond(
    !eq(mx, "MF2") : !div(!div(XMemorableVLEN, 2), sew),
    !eq(mx, "MF4") : !div(!div(XMemorableVLEN, 4), sew),
    !eq(mx, "MF8") : !div(!div(XMemorableVLEN, 8), sew),
    true: !div(!mul(XMemorableVLEN, LMUL), sew)
  );
}

// Latency for segmented loads and stores are calculated as vl * nf.
class XMemorableSegmentedLdStCycles<string mx, int sew, int nf> {
  int c = !mul(XMemorableGetVLMAX<mx, sew>.val, nf);
}

def XMemorableModel : SchedMachineModel {
  let IssueWidth        = 3; // one per dispatch lane (S/V/M), best case
  let MicroOpBufferSize = 0; // in-order
  let PostRAScheduler   = 1; // emission order is what dispatch sees
  let LoadLatency       = 3; // kept from the X60 skeleton
  let MispredictPenalty = 9; // kept from the X60 skeleton

  let CompleteModel = 1;

  // The xmemorable toolchain builds everything with
  // -march=rv64imafc_zve32f_zvl512b_xmemorable (plus zicsr/zifencei); every
  // extension below is one this machine does not implement, so the
  // completeness check skips its instructions. Standard extensions covered
  // by the X60 skeleton's WriteRes remap (I/M/A/F/C/B/V and friends) stay
  // supported; the custom ops are annotated in RISCVSchedXMemorableInstRW.td.
  let UnsupportedFeatures = [
    // Scalar crypto / entropy (X60's original list).
    HasStdExtZknd, HasStdExtZkne, HasStdExtZknh, HasStdExtZkndOrZkne,
    HasStdExtZksed, HasStdExtZksh, HasStdExtZkr,
    // Scalar FP beyond F: no D, no Q, no half, no BF16, no Zfa extras, and
    // none of the in-X-register (Zfinx-family) forms.
    HasStdExtD, HasStdExtQ, HasStdExtZfh, HasStdExtZfhmin, HasStdExtZfa,
    HasStdExtZfbfmin, HasStdExtZfinx, HasStdExtZdinx, HasStdExtZhinx,
    HasStdExtZhinxmin, HasHalfFPLoadStoreMove,
    // Atomics beyond A 2.1: CAS, byte/half AMOs, load-acquire/store-release.
    HasStdExtZacas, HasStdExtZabha, HasStdExtZalasr,
    // P (packed SIMD), shadow stacks / may-be-ops, paired/double scalar
    // loads, Zc extras, vector crypto bitmanip subset.
    HasStdExtP, HasStdExtZicfiss, HasStdExtZilsd, HasStdExtZclsd,
    HasStdExtZcmt, HasStdExtZcmp, HasStdExtZimop, HasStdExtZcmop,
    HasStdExtZvkb,
    // Short-forward-branch tune pseudos (no xmemorable tune CPU sets these).
    HasShortForwardBranchIALU, HasShortForwardBranchILoad,
    HasShortForwardBranchIMinMax, HasShortForwardBranchIMul,
    // Vector extensions beyond Zve32f: crypto/bitmanip, BF16, dot product.
    HasStdExtZvbb, HasStdExtZvfbfmin, HasStdExtZvfbfwma, HasStdExtZvfbfa,
    HasStdExtZvqdotq,
    // Vendor extensions (all other vendors' custom ops).
    HasVendorXTHeadBa, HasVendorXTHeadBb, HasVendorXTHeadBs,
    HasVendorXTHeadCmo, HasVendorXTHeadCondMov, HasVendorXTHeadFMemIdx,
    HasVendorXTHeadMac, HasVendorXTHeadMemIdx, HasVendorXTHeadMemPair,
    HasVendorXTHeadSync, HasVendorXTHeadVdot,
    HasVendorXSfvcp, HasVendorXSfvqmaccdod, HasVendorXSfvqmaccqoq,
    HasVendorXSfvfwmaccqqq, HasVendorXSfvfnrclipxfqf, HasVendorXSfcease,
    HasVendorXSfvfexpAny, HasVendorXSfvfexpAnyFloat, HasVendorXSfvfexpa,
    HasVendorXSfvfexpa64e, HasVendorXSfvfexp16e, HasVendorXSfvfbfexp16e,
    HasVendorXSfvfexp32e, HasVendorXSfmmbase, HasVendorXSfmm32a8f,
    HasVendorXSfmm32a8i, HasVendorXSfmm32a16fOrXSfmm32a32fOrXSfmm64a64f,
    HasVendorXSiFivecdiscarddlone, HasVendorXSiFivecflushdlone,
    HasVendorXCValu, HasVendorXCVbi, HasVendorXCVbitmanip, HasVendorXCVelw,
    HasVendorXCVmac, HasVendorXCVmem, HasVendorXCVsimd,
    HasVendorXqcia, HasVendorXqciac, HasVendorXqcibi, HasVendorXqcibm,
    HasVendorXqcicli, HasVendorXqcicm, HasVendorXqcics, HasVendorXqcicsr,
    HasVendorXqciint, HasVendorXqciio, HasVendorXqcilb, HasVendorXqcili,
    HasVendorXqcilia, HasVendorXqcilo, HasVendorXqcilsm, HasVendorXqcisim,
    HasVendorXqcisls, HasVendorXqcisync, HasVendorXqccmp,
    HasVendorXAndesBFHCvt, HasVendorXAndesPerf, HasVendorXAndesVBFHCvt,
    HasVendorXAndesVDot, HasVendorXAndesVPackFPH, HasVendorXAndesVSIntH,
    HasVendorXAndesVSIntLoad,
    HasVendorXRivosVisni, HasVendorXRivosVizip,
    HasVendorXMIPSCBOP, HasVendorXMIPSCMov, HasVendorXMIPSEXECTL,
    HasVendorXMIPSLSP, HasVendorXSMTVDot, HasVendorXVentanaCondOps
  ];
}

let SchedModel = XMemorableModel in {

//===----------------------------------------------------------------------===//
// Processor resources for the xmemorable node

// Two-tier resources (docs/superpowers/specs/2026-08-06-llvm-sched-model-design.md):
//
// Tier 1 -- dispatch lanes. The front end routes an in-order 3-slot window
// into three decoupled lanes (scalar / vector / matrix), at most one op per
// lane per cycle (dispatch_select.sv). Every instruction occupies its lane
// for exactly 1 cycle; adjacent same-lane instructions cannot co-issue, which
// is precisely what 1-wide ProcResources make the scheduler avoid.
//
// Tier 2 -- FU issue queues behind the vector/matrix lanes, BufferSize = 4
// (the issue-queue depth). Occupancy = beat count, giving the II=4 rhythm of
// m4 ops and the 16-beat matrix drain spacing without hand tuning.
//
// The X60 skeleton's scalar pipes (LS/IEUA/IEUB/IEU/FP) all map onto XMDispS;
// its vector resources (VLS/VIEU/VFP) map onto [XMDispV, XMFu<class>] with
// the FU class following the op family (loads -> XMFuLoad, stores ->
// XMFuStore, arith/FMA/mask/permute -> XMFuSfu). vset* stays scalar
// (XMDispS). X60 latencies are kept as-is: harmless defaults -- the lane
// resources are what drive interleaving.
def XMDispS   : ProcResource<1>;                        // scalar dispatch lane
def XMDispV   : ProcResource<1>;                        // vector dispatch lane
def XMDispM   : ProcResource<1>;                        // matrix dispatch lane
let BufferSize = 4 in {                                 // issue-queue depth
  def XMFuLoad   : ProcResource<1>;
  def XMFuSfu    : ProcResource<1>;
  def XMFuStore  : ProcResource<1>;
  def XMFuMatrix : ProcResource<1>;
}

//===----------------------------------------------------------------------===//

// Branching
def : WriteRes<WriteJmp, [XMDispS]>;
def : WriteRes<WriteJal, [XMDispS]>;
def : WriteRes<WriteJalr, [XMDispS]>;

// Integer arithmetic and logic
// Latency of ALU instructions is 1, but add.uw is 2
def : WriteRes<WriteIALU32, [XMDispS]>;
def : WriteRes<WriteIALU, [XMDispS]>;
def : WriteRes<WriteShiftImm32, [XMDispS]>;
def : WriteRes<WriteShiftImm, [XMDispS]>;
def : WriteRes<WriteShiftReg32, [XMDispS]>;
def : WriteRes<WriteShiftReg, [XMDispS]>;

// Integer multiplication
def : WriteRes<WriteIMul32, [XMDispS]>  { let Latency = 3; }

// The latency of mul is 5, while in mulh, mulhsu, mulhu is 6
// Worst case latency is used
def : WriteRes<WriteIMul, [XMDispS]>  { let Latency = 6; }

// Integer division/remainder
// TODO: Latency set based on C908 datasheet and hasn't been
// confirmed experimentally.
let Latency = 12, ReleaseAtCycles = [12] in {
  def : WriteRes<WriteIDiv32, [XMDispS]>;
  def : WriteRes<WriteIRem32, [XMDispS]>;
}
let Latency = 20, ReleaseAtCycles = [20] in {
  def : WriteRes<WriteIDiv, [XMDispS]>;
  def : WriteRes<WriteIRem, [XMDispS]>;
}

// Bitmanip
def : WriteRes<WriteRotateImm, [XMDispS]>;
def : WriteRes<WriteRotateImm32, [XMDispS]>;
def : WriteRes<WriteRotateReg, [XMDispS]>;
def : WriteRes<WriteRotateReg32, [XMDispS]>;

def : WriteRes<WriteCLZ, [XMDispS]>;
def : WriteRes<WriteCLZ32, [XMDispS]>;
def : WriteRes<WriteCTZ, [XMDispS]>;
def : WriteRes<WriteCTZ32, [XMDispS]>;

let Latency = 2 in {
  def : WriteRes<WriteCPOP, [XMDispS]>;
  def : WriteRes<WriteCPOP32, [XMDispS]>;
}

def : WriteRes<WriteORCB, [XMDispS]>;
def : WriteRes<WriteIMinMax, [XMDispS]>;
def : WriteRes<WriteREV8, [XMDispS]>;

let Latency = 2 in {
  def : WriteRes<WriteSHXADD, [XMDispS]>;
  def : WriteRes<WriteSHXADD32, [XMDispS]>;
  def : WriteRes<WriteCLMUL, [XMDispS]>;
}

// Single-bit instructions
def : WriteRes<WriteSingleBit, [XMDispS]>;
def : WriteRes<WriteSingleBitImm, [XMDispS]>;
def : WriteRes<WriteBEXT, [XMDispS]>;
def : WriteRes<WriteBEXTI, [XMDispS]>;

// Memory/Atomic memory
let Latency = 4 in {
  def : WriteRes<WriteSTB, [XMDispS]>;
  def : WriteRes<WriteSTH, [XMDispS]>;
  def : WriteRes<WriteSTW, [XMDispS]>;
  def : WriteRes<WriteSTD, [XMDispS]>;
  def : WriteRes<WriteFST16, [XMDispS]>;
  def : WriteRes<WriteFST32, [XMDispS]>;
  def : WriteRes<WriteFST64, [XMDispS]>;

  def : WriteRes<WriteLDB, [XMDispS]>;
  def : WriteRes<WriteLDH, [XMDispS]>;
  def : WriteRes<WriteLDW, [XMDispS]>;
  def : WriteRes<WriteLDD, [XMDispS]>;
  def : WriteRes<WriteFLD16, [XMDispS]>;
  def : WriteRes<WriteFLD32, [XMDispS]>;
  def : WriteRes<WriteFLD64, [XMDispS]>;
}

// Atomics
let Latency = 8 in {
  def : WriteRes<WriteAtomicSTW, [XMDispS]>;
  def : WriteRes<WriteAtomicSTD, [XMDispS]>;
  def : WriteRes<WriteAtomicLDW, [XMDispS]>;
  def : WriteRes<WriteAtomicLDD, [XMDispS]>;
}

let Latency = 12 in {
  def : WriteRes<WriteAtomicW, [XMDispS]>;
  def : WriteRes<WriteAtomicD, [XMDispS]>;
}

// Floating point units Half precision
let Latency = 4 in {
  def : WriteRes<WriteFAdd16, [XMDispS]>;
  def : WriteRes<WriteFMul16, [XMDispS]>;
  def : WriteRes<WriteFSGNJ16, [XMDispS]>;
  def : WriteRes<WriteFMinMax16, [XMDispS]>;
}
def : WriteRes<WriteFMA16, [XMDispS]> { let Latency = 5; }

let Latency = 12, ReleaseAtCycles = [12] in {
  def :  WriteRes<WriteFDiv16, [XMDispS]>;
  def :  WriteRes<WriteFSqrt16, [XMDispS]>;
}

// Single precision
let Latency = 4 in {
  def : WriteRes<WriteFAdd32, [XMDispS]>;
  def : WriteRes<WriteFMul32, [XMDispS]>;
  def : WriteRes<WriteFSGNJ32, [XMDispS]>;
  def : WriteRes<WriteFMinMax32, [XMDispS]>;
}
def : WriteRes<WriteFMA32, [XMDispS]> { let Latency = 5; }

let Latency = 15, ReleaseAtCycles = [15] in {
  def :  WriteRes<WriteFDiv32, [XMDispS]>;
  def :  WriteRes<WriteFSqrt32, [XMDispS]>;
}

// Double precision
let Latency = 5 in {
  def : WriteRes<WriteFAdd64, [XMDispS]>;
  def : WriteRes<WriteFMul64, [XMDispS]>;
  def : WriteRes<WriteFSGNJ64, [XMDispS]>;
}
def : WriteRes<WriteFMinMax64, [XMDispS]> { let Latency = 4; }
def : WriteRes<WriteFMA64, [XMDispS]> { let Latency = 6; }

let Latency = 22, ReleaseAtCycles = [22] in {
  def :  WriteRes<WriteFDiv64, [XMDispS]>;
  def :  WriteRes<WriteFSqrt64, [XMDispS]>;
}

// Conversions
let Latency = 6 in {
  def : WriteRes<WriteFCvtF16ToI32, [XMDispS]>;
  def : WriteRes<WriteFCvtF32ToI32, [XMDispS]>;
  def : WriteRes<WriteFCvtF32ToI64, [XMDispS]>;
  def : WriteRes<WriteFCvtF64ToI64, [XMDispS]>;
  def : WriteRes<WriteFCvtF64ToI32, [XMDispS]>;
  def : WriteRes<WriteFCvtF16ToI64, [XMDispS]>;
}

let Latency = 4 in {
  def : WriteRes<WriteFCvtI32ToF16, [XMDispS]>;
  def : WriteRes<WriteFCvtI32ToF32, [XMDispS]>;
  def : WriteRes<WriteFCvtI32ToF64, [XMDispS]>;
  def : WriteRes<WriteFCvtI64ToF16, [XMDispS]>;
  def : WriteRes<WriteFCvtI64ToF32, [XMDispS]>;
  def : WriteRes<WriteFCvtI64ToF64, [XMDispS]>;
  def : WriteRes<WriteFCvtF16ToF32, [XMDispS]>;
  def : WriteRes<WriteFCvtF16ToF64, [XMDispS]>;
  def : WriteRes<WriteFCvtF32ToF16, [XMDispS]>;
  def : WriteRes<WriteFCvtF32ToF64, [XMDispS]>;
  def : WriteRes<WriteFCvtF64ToF16, [XMDispS]>;
  def : WriteRes<WriteFCvtF64ToF32, [XMDispS]>;
}

let Latency = 6 in {
  def : WriteRes<WriteFClass16, [XMDispS]>;
  def : WriteRes<WriteFClass32, [XMDispS]>;
  def : WriteRes<WriteFClass64, [XMDispS]>;

  def : WriteRes<WriteFCmp16, [XMDispS]>;
  def : WriteRes<WriteFCmp32, [XMDispS]>;
  def : WriteRes<WriteFCmp64, [XMDispS]>;

  def : WriteRes<WriteFMovF32ToI32, [XMDispS]>;
  def : WriteRes<WriteFMovF16ToI16, [XMDispS]>;
}

let Latency = 4 in {
  def : WriteRes<WriteFMovI16ToF16, [XMDispS]>;
  def : WriteRes<WriteFMovF64ToI64, [XMDispS]>;
  def : WriteRes<WriteFMovI64ToF64, [XMDispS]>;
  def : WriteRes<WriteFMovI32ToF32, [XMDispS]>;
}

// 6. Configuration-Setting Instructions
def : WriteRes<WriteVSETVLI, [XMDispS]>;
def : WriteRes<WriteVSETIVLI, [XMDispS]>;
def : WriteRes<WriteVSETVL, [XMDispS]>;

// 7. Vector Loads and Stores
foreach mx = SchedMxList in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxList>.c;

  // Unit-stride loads and stores
  defvar VLDELatAndOcc = XMemorableConstValueUntilLMULThenDoubleBase<"M2", 3, 4, mx>.c;
  let Latency = VLDELatAndOcc, ReleaseAtCycles = [1, VLDELatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVLDE", [XMDispV, XMFuLoad], mx, IsWorstCase>;
  }
  defvar VSTELatAndOcc = XMemorableGetLMULValue<[2, 2, 2, 3, 4, 8, 19], mx>.c;
  let Latency = VSTELatAndOcc, ReleaseAtCycles = [1, VSTELatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVSTE", [XMDispV, XMFuStore], mx, IsWorstCase>;
  }
  defvar VLDFFLatAndOcc = XMemorableGetLMULValue<[4, 4, 4, 5, 7, 11, 19], mx>.c;
  let Latency = VLDFFLatAndOcc, ReleaseAtCycles = [1, VLDFFLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVLDFF", [XMDispV, XMFuLoad], mx, IsWorstCase>;
  }

  // Mask loads and stores
  let ReleaseAtCycles = [1, 2] in {
    defm "" : LMULWriteResMX<"WriteVLDM", [XMDispV, XMFuLoad], mx, IsWorstCase>;
  }
  let Latency = 2, ReleaseAtCycles = [1, 2] in {
    defm "" : LMULWriteResMX<"WriteVSTM", [XMDispV, XMFuStore], mx, IsWorstCase>;
  }

  // Strided and indexed loads and stores
  foreach eew = [8, 16, 32, 64] in {
    defvar StridedLdStLatAndOcc = XMemorableGetVLMAX<mx, eew>.val;
    let Latency = StridedLdStLatAndOcc, ReleaseAtCycles = [1, StridedLdStLatAndOcc] in {
      defm "" : LMULWriteResMX<"WriteVLDS"  # eew, [XMDispV, XMFuLoad], mx, IsWorstCase>;
      defm "" : LMULWriteResMX<"WriteVSTS"  # eew, [XMDispV, XMFuStore], mx, IsWorstCase>;
    }

    defvar IndexedLdStLatAndOcc = !div(XMemorableGetVLMAX<mx, eew>.val, 2);
    let Latency = IndexedLdStLatAndOcc, ReleaseAtCycles = [1, IndexedLdStLatAndOcc] in {
      defm "" : LMULWriteResMX<"WriteVLDUX" # eew, [XMDispV, XMFuLoad], mx, IsWorstCase>;
      defm "" : LMULWriteResMX<"WriteVLDOX" # eew, [XMDispV, XMFuLoad], mx, IsWorstCase>;

      defm "" : LMULWriteResMX<"WriteVSTUX" # eew, [XMDispV, XMFuStore], mx, IsWorstCase>;
      defm "" : LMULWriteResMX<"WriteVSTOX" # eew, [XMDispV, XMFuStore], mx, IsWorstCase>;
    }
  }
}

// Segmented loads and stores
foreach mx = SchedMxList in {
  foreach nf=2-8 in {
    foreach eew = [8, 16, 32, 64] in {
      defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxList>.c;

      defvar SegmentedLdStLatAndOcc = XMemorableSegmentedLdStCycles<mx, eew, nf>.c;
      let Latency = SegmentedLdStLatAndOcc, ReleaseAtCycles = [1, SegmentedLdStLatAndOcc] in {
        // Unit-stride segmented
        defm "" : LMULWriteResMX<"WriteVLSEG" # nf # "e" #eew, [XMDispV, XMFuLoad], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVLSEGFF" # nf # "e" #eew, [XMDispV, XMFuLoad], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVSSEG" # nf # "e" #eew, [XMDispV, XMFuStore], mx, IsWorstCase>;

        // Strided/indexed segmented
        defm "" : LMULWriteResMX<"WriteVLSSEG" # nf # "e" #eew, [XMDispV, XMFuLoad], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVSSSEG" # nf # "e" #eew, [XMDispV, XMFuStore], mx, IsWorstCase>;

        // Indexed segmented
        defm "" : LMULWriteResMX<"WriteVLOXSEG" # nf # "e" #eew, [XMDispV, XMFuLoad], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVLUXSEG" # nf # "e" #eew, [XMDispV, XMFuLoad], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVSUXSEG" # nf # "e" #eew, [XMDispV, XMFuStore], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVSOXSEG" # nf # "e" #eew, [XMDispV, XMFuStore], mx, IsWorstCase>;
      }
    }
  }
}

// Whole register move/load/store
foreach LMul = [1, 2, 4, 8] in {
  defvar WholeRegLdStLatAndOcc = !if(!eq(LMul, 1), 3, !mul(LMul, 2));
  let Latency = WholeRegLdStLatAndOcc, ReleaseAtCycles = [1, WholeRegLdStLatAndOcc] in {
    def : WriteRes<!cast<SchedWrite>("WriteVLD" # LMul # "R"), [XMDispV, XMFuLoad]>;
    def : WriteRes<!cast<SchedWrite>("WriteVST" # LMul # "R"), [XMDispV, XMFuStore]>;
  }

  defvar VMovLatAndOcc = !if(!eq(LMul, 1), 4, !mul(LMul, 2));
  let Latency = VMovLatAndOcc, ReleaseAtCycles = [1, VMovLatAndOcc] in {
    def : WriteRes<!cast<SchedWrite>("WriteVMov" # LMul # "V"), [XMDispV, XMFuSfu]>;
  }
}

// 11. Vector Integer Arithmetic Instructions
foreach mx = SchedMxList in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxList>.c;

  let Latency = XMemorableGet4458Latency<mx>.c, ReleaseAtCycles = [1, XMemorableConstOneUntilM1ThenDouble<mx>.c] in {
    defm "" : LMULWriteResMX<"WriteVIMinMaxV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMinMaxX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  // Latency of vadd, vsub, vrsub:         4/4/5/8
  // ReleaseAtCycles of vadd, vsub, vrsub: 1/2/4/8
  // Latency of vand, vor, vxor:           4/4/8/16
  // ReleaseAtCycles of vand, vor, vxor:   2/4/8/16
  // They are grouped together, so we used the worst case 4/4/8/16 and 2/4/8/16
  // TODO: use InstRW to override individual instructions' scheduling data
  defvar VIALULat = XMemorableConstValueUntilLMULThenDouble<"M2", 4, mx>.c;
  defvar VIALUOcc = XMemorableConstOneUntilMF2ThenDouble<mx>.c;
  let Latency = VIALULat, ReleaseAtCycles = [1, VIALUOcc] in {
    defm "" : LMULWriteResMX<"WriteVIALUV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIALUX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIALUI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  let Latency = VIALULat in
  def XMemorableWriteVCOPY_ # mx : SchedWriteRes<[]>;

  defvar VILogicalLat = XMemorableConstValueUntilLMULThenDouble<"M2", 4, mx>.c;
  defvar VILogicalOcc = XMemorableConstValueUntilLMULThenDouble<"MF2", 1, mx>.c;
  let Latency = VILogicalLat, ReleaseAtCycles = [1, VILogicalOcc] in {
    defm "" : LMULWriteResMX<"WriteVExtV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMergeV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMergeX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMergeI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMovV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMovX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMovI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVShiftV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVShiftX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVShiftI", [XMDispV, XMFuSfu], mx, IsWorstCase>;

    defm "" : LMULWriteResMX<"WriteVICALUV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICALUX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICALUI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  // Slightly increase Occ when LMUL == M8
  defvar VICmpCarryOcc = XMemorableGetLMULValue<[1, 1, 1, 2, 4, 8, 18], mx>.c;
  let Latency = XMemorableGet461018Latency<mx>.c, ReleaseAtCycles = [1, VICmpCarryOcc] in {
    defm "" : LMULWriteResMX<"WriteVICALUMV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICALUMX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICALUMI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICmpV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICmpX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICmpI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  // Latency of vmacc, vmadd, vmul, vmulh, etc.: e8/e16 = 4/4/5/8, e32 = 5,5,5,8,
  // e64 = 7,8,16,32. We use the worst-case until we can split the SEW.
  // TODO: change WriteVIMulV, etc to be defined with LMULSEWSchedWrites
  defvar VIMulLat = XMemorableConstValueUntilLMULThenDoubleBase<"M2", 7, 8, mx>.c;
  // ReleaseAtCycles for vnmsac/vnmsub is 1/1/1/1/2/5 but we use the worse case
  // here since they are grouped together with vmacc/vmadd/vmul/vmulh.
  defvar VIMulOcc = XMemorableConstOneUntilM1ThenDouble<mx>.c;
  let Latency = VIMulLat, ReleaseAtCycles = [1, VIMulOcc] in {
    defm "" : LMULWriteResMX<"WriteVIMulV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMulX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMulAddV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMulAddX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
}

// Widening
// Pattern of vwmul, vwmacc, etc: e8/e16 = 4/4/5/8, e32 = 5,5,5,8
// We use the worst-case for all.
foreach mx = SchedMxListW in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxListW>.c;

  defvar VIWideningOcc = XMemorableConstOneUntilMF2ThenDouble<mx>.c;
  let Latency = XMemorableGet4588Latency<mx>.c, ReleaseAtCycles = [1, VIWideningOcc]  in {
    defm "" : LMULWriteResMX<"WriteVIWALUV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWALUX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWALUI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWMulV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWMulX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWMulAddV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWMulAddX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
}

// Division and remainder operations
// Pattern of vdivu: 11/11/11/20/40/80/160
// Pattern of vdiv: 12/12/12/22/44/88/176
// Pattern of vremu: 12/12/12/22/44/88/176
// Pattern of vrem: 13/13/13/24/48/96/192
// We use for all: 12/12/12/24/48/96/192
// TODO: Create separate WriteVIRem to more closely match the latencies
foreach mx = SchedMxList in {
  foreach sew = SchedSEWSet<mx>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxList>.c;

    // Not pipelined
    defvar VIDivLatAndOcc = XMemorableConstValueUntilLMULThenDouble<"MF2", 12, mx>.c;
    let Latency = VIDivLatAndOcc, ReleaseAtCycles = [1, VIDivLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVIDivV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVIDivX", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

// Narrowing Shift and Clips
foreach mx = SchedMxListW in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxListW>.c;

  defvar VNarrowingLat = XMemorableConstValueUntilLMULThenDouble<"M1", 4, mx>.c;
  defvar VNarrowingOcc = XMemorableConstValueUntilLMULThenDouble<"MF4", 1, mx>.c;
  let Latency = VNarrowingLat, ReleaseAtCycles = [1, VNarrowingOcc] in {
    defm "" : LMULWriteResMX<"WriteVNShiftV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNShiftX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNShiftI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNClipV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNClipX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNClipI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
}

// 12. Vector Fixed-Point Arithmetic Instructions
foreach mx = SchedMxList in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxList>.c;

  let Latency = XMemorableGet4458Latency<mx>.c, ReleaseAtCycles = [1, XMemorableConstOneUntilM1ThenDouble<mx>.c] in {
    defm "" : LMULWriteResMX<"WriteVSALUV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSALUX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSALUI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVAALUV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVAALUX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  // Latency of vsmul: e8/e16 = 4/4/5/8, e32 = 5/5/5/8, e64 = 7/8/16/32
  // We use the worst-case until we can split the SEW.
  defvar VSMulLat = XMemorableConstValueUntilLMULThenDoubleBase<"M2", 7, 8, mx>.c;
  // Latency of vsmul: e8/e16/e32 = 1/2/4/8, e64 = 4/8/16/32
  // We use the worst-case until we can split the SEW.
  defvar VSMulOcc = XMemorableConstValueUntilLMULThenDoubleBase<"M1", 1, 4, mx>.c;
  // TODO: change WriteVSMulV/X to be defined with LMULSEWSchedWrites
  let Latency = VSMulLat, ReleaseAtCycles = [1, VSMulOcc] in {
    defm "" : LMULWriteResMX<"WriteVSMulV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSMulX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  defvar VSShiftLat = XMemorableConstValueUntilLMULThenDouble<"M2", 4, mx>.c;
  defvar VSShiftOcc = XMemorableConstOneUntilMF2ThenDouble<mx>.c;
  let Latency = VSShiftLat, ReleaseAtCycles = [1, VSShiftOcc] in {
    defm "" : LMULWriteResMX<"WriteVSShiftV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSShiftX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSShiftI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
}

// 13. Vector Floating-Point Instructions
foreach mx = SchedMxListF in {
  foreach sew = SchedSEWSet<mx, isF=1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListF, isF=1>.c;

    defvar VFALULat = XMemorableGet4458Latency<mx>.c;
    defvar VFALUOcc = XMemorableConstOneUntilM1ThenDouble<mx>.c;
    let Latency = VFALULat, ReleaseAtCycles = [1, VFALUOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFALUV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFALUF", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMinMaxV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMinMaxF", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }

    // Slightly increased latency for sew == 64
    defvar VFMulVLat = !if(!eq(sew, 64), XMemorableConstValueUntilLMULThenDoubleBase<"M8", 5, 8, mx>.c,
                                               XMemorableGet4458Latency<mx>.c);
    let Latency = VFMulVLat, ReleaseAtCycles = [1, XMemorableConstOneUntilM1ThenDouble<mx>.c] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMulV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
    // VFMulF has the same latency as VFMulV, but slighlty lower ReleaseAtCycles
    let Latency = VFMulVLat, ReleaseAtCycles = [1, XMemorableConstOneUntilM1ThenDouble<mx>.c] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMulF", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }

    defvar VFSgnjLat = XMemorableConstValueUntilLMULThenDouble<"M2", 4, mx>.c;
    defvar VFSgnjOcc = XMemorableConstOneUntilMF2ThenDouble<mx>.c;
    let Latency = VFSgnjLat, ReleaseAtCycles = [1, VFSgnjOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFRecpV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFSgnjV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFSgnjF", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFCvtIToFV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }

    // The following covers vfmacc, vfmsac, and their vfn* variants in the same group, but the
    // ReleaseAtCycles takes one extra cycle for the vfn* variants.
    // TODO: Should we split them?
    // TODO: for some reason, the following cond is not working, and always use XMemorableConstValueUntilLMULThenDoubleBase<"M4", 5, 8, mx>.c
    defvar VFMulAddLatency = !if(!eq(sew, 64),
      XMemorableGet6678Latency<mx>.c,
      XMemorableConstValueUntilLMULThenDoubleBase<"M8", 5, 8, mx>.c
    );
    let Latency = VFMulAddLatency, ReleaseAtCycles = [1, XMemorableConstOneUntilM1ThenDouble<mx>.c] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMulAddV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMulAddF", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

foreach mx = SchedMxList in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxList>.c;

  // Slightly increased ReleaseAtCycles for M8: 18
  defvar VFCmpOcc = !if(!eq(mx, "M8"),
    !add(XMemorableConstOneUntilMF2ThenDouble<mx>.c, 2),
    XMemorableConstOneUntilMF2ThenDouble<mx>.c
  );
  let Latency = XMemorableGet461018Latency<mx>.c, ReleaseAtCycles = [1, VFCmpOcc] in {
    defm "" : LMULWriteResMX<"WriteVFCmpV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFCmpF", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  defvar VFClassLat = XMemorableConstValueUntilLMULThenDouble<"M2", 4, mx>.c;
  defvar VFClassOcc = XMemorableConstOneUntilMF2ThenDouble<mx>.c;
  let Latency = VFClassLat, ReleaseAtCycles = [1, VFClassOcc] in {
    defm "" : LMULWriteResMX<"WriteVFClassV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFMergeV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFMovV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFCvtFToIV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
}

// Widening
foreach mx = SchedMxListW in {
  foreach sew = SchedSEWSet<mx, isF=0, isWidening=1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListW>.c;

    defvar VFWCvtILat = XMemorableConstValueUntilLMULThenDouble<"M1", 4, mx>.c;
    defvar VFWCvtIOcc = XMemorableConstOneUntilMF4ThenDouble<mx>.c;
    let Latency = VFWCvtILat, ReleaseAtCycles = [1, VFWCvtIOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWCvtIToFV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

foreach mx = SchedMxListFW in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxListFW>.c;

  defvar VFWCvtFToIVLat = XMemorableConstValueUntilLMULThenDouble<"M1", 4, mx>.c;
  defvar VFWCvtFToIVOcc = XMemorableConstOneUntilMF4ThenDouble<mx>.c;
  let Latency = VFWCvtFToIVLat, ReleaseAtCycles = [1, VFWCvtFToIVOcc] in {
    defm "" : LMULWriteResMX<"WriteVFWCvtFToIV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
}

foreach mx = SchedMxListFW in {
  foreach sew = SchedSEWSet<mx, isF=1, isWidening=1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListFW, isF=1>.c;

    defvar VFWCvtFToFVLat = XMemorableConstValueUntilLMULThenDouble<"M1", 4, mx>.c;
    defvar VFWCvtFToFVOcc = XMemorableConstOneUntilMF4ThenDouble<mx>.c;
    let Latency = VFWCvtFToFVLat, ReleaseAtCycles = [1, VFWCvtFToFVOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWCvtFToFV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }

    // Latency for vfwsub/vfwadd.vv, vfwsub/vfwadd.vf: 4/4/4/5/8
    // ReleaseAtCycles for vfwsub/vfwadd.vv, vfwsub/vfwadd.vf: 1/1/2/4/8
    // Latency for vfwsub/vfwadd.wv, vfwsub/vfwadd.wf: 5/5/5/9/17
    // ReleaseAtCycles for vfwsub/vfwadd.wv, vfwsub/vfwadd.wf: 1/2/4/8/17
    // We use the worst-case
    defvar VFWALULat = !add(XMemorableConstValueUntilLMULThenDouble<"M1", 4, mx>.c, 1); // 5/5/9/17
    defvar VFWALUOcc = !if(!eq(mx, "M4"),
      !add(XMemorableConstOneUntilMF4ThenDouble<mx>.c, 1), // 2/4/8/17
      XMemorableConstOneUntilMF4ThenDouble<mx>.c
    );
    // TODO: Split .wf/.wv variants into separate scheduling classes
    let Latency = VFWALULat, ReleaseAtCycles = [1, VFWALUOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWALUV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWALUF", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }

    let Latency = XMemorableGet4588Latency<mx>.c, ReleaseAtCycles = [1, XMemorableConstOneUntilMF2ThenDouble<mx>.c] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWMulF", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }

    // Slightly increased latency for SEW == 32
    defvar VFWMullOcc = !if(!eq(sew, 32),
      XMemorableGetLMULValue<[1, 1, 1, 3, 5, 9, 18], mx>.c,
      XMemorableConstOneUntilMF2ThenDouble<mx>.c
    );
    defvar VFWMulVLat = XMemorableConstValueUntilLMULThenDoubleBase<"M8", 5, 8, mx>.c;
    let Latency = VFWMulVLat, ReleaseAtCycles = [1, VFWMullOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWMulV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }

    // Latency for vfwmacc, vfwnmacc, etc: e16 = 5/5/5/8; e32 = 6/6/7/8
    defvar VFWMulAddVLat = !if(!eq(sew, 16),
      XMemorableConstValueUntilLMULThenDoubleBase<"M4", 5, 8, mx>.c,
      XMemorableGet6678Latency<mx>.c
    );
    let Latency = VFWMulAddVLat, ReleaseAtCycles = [1, XMemorableConstOneUntilMF2ThenDouble<mx>.c] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWMulAddV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWMulAddF", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

// Narrowing
foreach mx = SchedMxListW in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxListW>.c;

  defvar VFNCvtFToIVLat = XMemorableConstValueUntilLMULThenDouble<"M1", 4, mx>.c;
  defvar VFNCvtFToIVOcc = XMemorableConstOneUntilMF4ThenDouble<mx>.c;
  let Latency = VFNCvtFToIVLat, ReleaseAtCycles = [1, VFNCvtFToIVOcc] in {
    defm "" : LMULWriteResMX<"WriteVFNCvtFToIV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
}

foreach mx = SchedMxListFW in {
  foreach sew = SchedSEWSet<mx, isF=1, isWidening=1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListFW, isF=1>.c;

    defvar VFNCvtToFVLat = XMemorableConstValueUntilLMULThenDouble<"M1", 4, mx>.c;
    defvar VFNCvtToFVOcc = XMemorableConstOneUntilMF4ThenDouble<mx>.c;
    let Latency = VFNCvtToFVLat, ReleaseAtCycles = [1, VFNCvtToFVOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFNCvtIToFV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFNCvtFToFV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

// Vector Floating-Point Division and Square Root
foreach mx = SchedMxListF in {
  foreach sew = SchedSEWSet<mx, 1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListF, 1>.c;

    // Compute ReleaseAtCycles based on SEW
    // Latency for vfdiv.vf: e16/e32 = 12/24/48/96; e64 = 18/36/72/144
    // Latency for vfrdiv.vf: e16/e32 = 12/24/48/96; e64 = 40/80/160/320
    // We use the worst-case, vfdiv.vf is penalized in e64
    // TODO: split vfdiv.vf and vfrdiv.vf into separate scheduling classes
    defvar VFDivFFactor = !if(!eq(sew, 64), 40, 12);
    defvar VFDivFLatAndOcc = !mul(XMemorableConstOneUntilM1ThenDouble<mx>.c, VFDivFFactor);
    let Latency = VFDivFLatAndOcc, ReleaseAtCycles = [1, VFDivFLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFDivF", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }

    defvar VFDivVFactor = !if(!eq(sew, 16), 12, 40);
    defvar VFDivVLatAndOcc = !mul(XMemorableConstOneUntilM1ThenDouble<mx>.c, VFDivVFactor);
    let Latency = VFDivVLatAndOcc, ReleaseAtCycles = [1, VFDivVLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFDivV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

// Pattern for vfsqrt.v: e16 = 18/36/72/144; e32 = 38/76/152/304; e64 = 40/80/160/320
foreach mx = SchedMxListF in {
  foreach sew = SchedSEWSet<mx, 1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListF, 1>.c;

    defvar VFSqrtVFactor = !if(!eq(sew, 16), 12, 40);
    defvar VFSqrtVLatAndOcc = !mul(XMemorableConstOneUntilM1ThenDouble<mx>.c, VFSqrtVFactor);
    let Latency = VFSqrtVLatAndOcc, ReleaseAtCycles = [1, VFSqrtVLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFSqrtV", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

// 14. Vector Reduction Operations
foreach mx = SchedMxList in {
  foreach sew = SchedSEWSet<mx>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxList>.c;

    defvar VIRedLat = XMemorableGetLMULValue<[5, 5, 5, 7, 11, 19, 35], mx>.c;
    defvar VIRedOcc = XMemorableGetLMULValue<[1, 1, 2, 2, 4, 10, 35], mx>.c;
    let Latency = VIRedLat, ReleaseAtCycles = [1, VIRedOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVIRedMinMaxV_From", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;

      // Pattern for vredsum:                  5/5/5/7/11/19/35
      // Pattern for vredand, vredor, vredxor: 4/4/4/6/10/18/34
      // They are grouped together, so we use the worst-case vredsum latency.
      // TODO: split vredand, vredor, vredxor into separate scheduling classe.
      defm "" : LMULSEWWriteResMXSEW<"WriteVIRedV_From", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

foreach mx = SchedMxListWRed in {
  foreach sew = SchedSEWSet<mx, 0, 1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListWRed>.c;

    defvar VIRedLat = XMemorableGetLMULValue<[5, 5, 5, 7, 11, 19, 35], mx>.c;
    defvar VIRedOcc = XMemorableGetLMULValue<[1, 1, 2, 2, 4, 10, 35], mx>.c;
    let Latency = VIRedLat, ReleaseAtCycles = [1, VIRedOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVIWRedV_From", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

foreach mx = SchedMxListF in {
  foreach sew = SchedSEWSet<mx, 1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListF, 1>.c;

    // Latency for vfredmax.vs, vfredmin.vs: 12/12/15/21/33/57
    // Latency for vfredusum.vs is slightly lower for e16/e32
    // We use the worst-case
    defvar VFRedLat = XMemorableGetLMULValue<[12, 12, 12, 15, 21, 33, 57], mx>.c;
    defvar VFRedOcc = XMemorableGetLMULValue<[8, 8, 8, 8, 14, 20, 57], mx>.c;
    let Latency = VFRedLat, ReleaseAtCycles = [1, VFRedOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFRedV_From", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFRedMinMaxV_From", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

foreach mx = SchedMxListF in {
  foreach sew = SchedSEWSet<mx, 1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListF, 1>.c;

    // Compute latency based on SEW
    defvar VFRedOV_FromLat = !cond(
      !eq(sew, 16) : XMemorableConstValueUntilLMULThenDouble<"MF4", 12, mx>.c,
      !eq(sew, 32) : XMemorableConstValueUntilLMULThenDouble<"MF2", 12, mx>.c,
      !eq(sew, 64) : XMemorableConstValueUntilLMULThenDouble<"M1", 12, mx>.c
    );
    defvar VFRedOV_FromOcc = !cond(
      !eq(sew, 16) : XMemorableGetLMULValue<[8, 8, 20, 24, 48, 96, 384], mx>.c,
      !eq(sew, 32) : XMemorableGetLMULValue<[8, 8,  8, 12, 24, 48, 192], mx>.c,
      !eq(sew, 64) : XMemorableGetLMULValue<[6, 6,  6,  6, 12, 24,  96], mx>.c
    );
    let Latency = VFRedOV_FromLat, ReleaseAtCycles = [1, VFRedOV_FromOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFRedOV_From", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

foreach mx = SchedMxListFWRed in {
  foreach sew = SchedSEWSet<mx, 1, 1>.val in {
    defvar IsWorstCase = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxListFWRed, 1>.c;

    defvar VFRedOVLat = !cond(
      !eq(sew, 16) : XMemorableConstValueUntilLMULThenDouble<"MF4", 16, mx>.c,
      !eq(sew, 32) : XMemorableConstValueUntilLMULThenDouble<"MF2", 16, mx>.c,
    );
    defvar VFRedOVOcc = !cond(
      !eq(sew, 16) : XMemorableGetLMULValue<[11, 11, 27, 32, 64, 128, 512], mx>.c,
      !eq(sew, 32) : XMemorableGetLMULValue<[11, 11, 11, 16, 32,  64, 256], mx>.c,
    );
    let Latency = VFRedOVLat, ReleaseAtCycles = [1, VFRedOVOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWRedV_From", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWRedOV_From", [XMDispV, XMFuSfu], mx, sew, IsWorstCase>;
    }
  }
}

// 15. Vector Mask Instructions
foreach mx = SchedMxList in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxList>.c;

  let Latency = 4 in {
    defm "" : LMULWriteResMX<"WriteVMALUV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
  let Latency = 4, ReleaseAtCycles = [1, XMemorableConstValueUntilLMULThenDouble<"M2", 1, mx>.c] in {
    defm "" : LMULWriteResMX<"WriteVMSFSV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  let Latency = 6, ReleaseAtCycles = [1, 2] in {
    defm "" : LMULWriteResMX<"WriteVMPopV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVMFFSV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  defvar VIotaLat = XMemorableConstValueUntilLMULThenDouble<"M2", 4, mx>.c;
  defvar VIotaOcc = XMemorableConstOneUntilMF2ThenDouble<mx>.c;
  let Latency = VIotaLat, ReleaseAtCycles = [1, VIotaOcc] in {
    defm "" : LMULWriteResMX<"WriteVIotaV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIdxV", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
}

// 16. Vector Permutation Instructions
// Slide
foreach mx = SchedMxList in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxList>.c;

  // Latency for slide up: 4/4/8/16, ReleaseAtCycles is 2/4/8/16
  defvar VSlideUpLat = XMemorableConstValueUntilLMULThenDouble<"M2", 4, mx>.c;
  defvar VSlideUpOcc = XMemorableConstOneUntilMF2ThenDouble<mx>.c;
  let Latency = VSlideUpLat, ReleaseAtCycles = [1, VSlideUpOcc] in {
    defm "" : LMULWriteResMX<"WriteVSlideUpX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  // Latency for slide down: 4/5/9/17, ReleaseAtCycles is 3/5/9/17
  defvar VSlideDownLat = XMemorableGetLMULValue<[4, 4, 4, 4, 5, 9, 17], mx>.c;
  defvar VSlideDownOcc = XMemorableGetLMULValue<[1, 1, 1, 3, 5, 9, 17], mx>.c;
  let Latency = VSlideDownLat, ReleaseAtCycles = [1, VSlideDownOcc] in {
    defm "" : LMULWriteResMX<"WriteVSlideDownX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
  // The following group slide up and down together, so we use the worst-case
  // (slide down) for all.
  let Latency = VSlideDownLat, ReleaseAtCycles = [1, VSlideDownOcc] in {
    defm "" : LMULWriteResMX<"WriteVSlideI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVISlide1X", [XMDispV, XMFuSfu], mx, IsWorstCase>;

    defm "" : LMULWriteResMX<"WriteVFSlide1F", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }
}

// ReleaseAtCycles is 2/2/2/2/2/3/6, but we can't set based on MX for now
// TODO: Split this into separate WriteRes for each MX
let Latency = 6, ReleaseAtCycles = [1, 6] in {
  def : WriteRes<WriteVMovXS, [XMDispV, XMFuSfu]>;
}

// ReleaseAtCycles is 1/1/1/1/1/2/4, but we can't set based on MX for now
// TODO: Split this into separate WriteRes for each MX
let Latency = 4, ReleaseAtCycles = [1, 4] in {
  def : WriteRes<WriteVMovSX, [XMDispV, XMFuSfu]>;
  def : WriteRes<WriteVMovFS, [XMDispV, XMFuSfu]>;
  def : WriteRes<WriteVMovSF, [XMDispV, XMFuSfu]>;
}

// Integer LMUL Gather and Compress
foreach mx = SchedMxList in {
  defvar IsWorstCase = XMemorableIsWorstCaseMX<mx, SchedMxList>.c;

  defvar VRGatherLat = XMemorableConstValueUntilLMULThenDouble<"M2", 4, mx>.c;
  let Latency = VRGatherLat, ReleaseAtCycles = [1, XMemorableConstOneUntilMF2ThenDouble<mx>.c] in {
    defm "" : LMULWriteResMX<"WriteVRGatherVX", [XMDispV, XMFuSfu], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVRGatherVI", [XMDispV, XMFuSfu], mx, IsWorstCase>;
  }

  foreach sew = SchedSEWSet<mx>.val in {
    defvar IsWorstCaseSEW = XMemorableIsWorstCaseMXSEW<mx, sew, SchedMxList>.c;

    defvar VRGatherVVLat = XMemorableGetLMULValue<[4, 4, 4, 4, 16, 64, 256], mx>.c;
    defvar VRGatherVVOcc = XMemorableGetLMULValue<[1, 1, 1, 4, 16, 64, 256], mx>.c;
    let Latency = VRGatherVVLat, ReleaseAtCycles = [1, VRGatherVVOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVRGatherVV", [XMDispV, XMFuSfu], mx, sew, IsWorstCaseSEW>;
    }
    // For sew == 8, latency is half of the other cases, except for the fractional LMULs (const 4 cycles)
    defvar VRGatherEI16Lat = !if(!eq(sew, 8),
      XMemorableGetLMULValue<[4, 4, 4, 8, 32, 128, 256], mx>.c,
      XMemorableGetLMULValue<[4, 4, 4, 4, 16,  64, 256], mx>.c);
    defvar VRGatherEI16Occ = !if(!eq(sew, 8),
      XMemorableGetLMULValue<[1, 1, 2, 8, 32, 128, 256], mx>.c,
      XMemorableGetLMULValue<[1, 1, 1, 4, 16,  64, 256], mx>.c);
    let Latency = VRGatherEI16Lat, ReleaseAtCycles = [1, VRGatherEI16Occ] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVRGatherEI16VV", [XMDispV, XMFuSfu], mx, sew, IsWorstCaseSEW>;
    }

    defvar VCompressVLat = XMemorableGetLMULValue<[4, 4, 4, 4, 10, 36, 136], mx>.c;
    defvar VCompressVOcc = XMemorableGetLMULValue<[1, 1, 1, 3, 10, 36, 136], mx>.c;
    let Latency = VCompressVLat, ReleaseAtCycles = [1, VCompressVOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVCompressV", [XMDispV, XMFuSfu], mx, sew, IsWorstCaseSEW>;
    }
  }
}

// Others
def : WriteRes<WriteCSR, [XMDispS]>;
def : WriteRes<WriteNop, [XMDispS]>;
def : WriteRes<WriteRdVLENB, [XMDispS]>;

// Assign scheduling info to COPY instructions.
// Note: We try NOT to assign ProcResource but only latency to vector COPY because
// those resources might prevent those COPYs from showing up to the scheulder
// until it's too late.
// Specifically, for a given COPY of live-in (physical) register, ideally we want it
// to be visible to the top available queue as early as possible so that it can be scheduled
// at the beginning of the function. Assigning resource to vector COPYs might risk
// creating structural hazard that prevents those COPYs from even entering the available
// queue and as a consequence, sinking those COPYs.
// I see little difference on assigning ProcResource to scalar COPY or not, so I'm still
// assigning WriteIALU to it.
def XMemorableCopySchedWriteVariant : SchedWriteVariant<[
  SchedVar<SchedPredicate<[{ TII->isVRegCopy(MI, /*LMUL=*/1) }]>, [XMemorableWriteVCOPY_M1]>,
  SchedVar<SchedPredicate<[{ TII->isVRegCopy(MI, /*LMUL=*/2) }]>, [XMemorableWriteVCOPY_M2]>,
  SchedVar<SchedPredicate<[{ TII->isVRegCopy(MI, /*LMUL=*/4) }]>, [XMemorableWriteVCOPY_M4]>,
  SchedVar<SchedPredicate<[{ TII->isVRegCopy(MI, /*LMUL=*/8) }]>, [XMemorableWriteVCOPY_M8]>,
  SchedVar<NoSchedPred,                                           [WriteIALU]>
]>;
def : InstRW<[XMemorableCopySchedWriteVariant], (instrs COPY)>;

//===----------------------------------------------------------------------===//
// Bypass and advance
def : ReadAdvance<ReadJmp, 0>;
def : ReadAdvance<ReadJalr, 0>;
def : ReadAdvance<ReadCSR, 0>;
def : ReadAdvance<ReadStoreData, 0>;
def : ReadAdvance<ReadMemBase, 0>;
def : ReadAdvance<ReadIALU, 0>;
def : ReadAdvance<ReadIALU32, 0>;
def : ReadAdvance<ReadShiftImm, 0>;
def : ReadAdvance<ReadShiftImm32, 0>;
def : ReadAdvance<ReadShiftReg, 0>;
def : ReadAdvance<ReadShiftReg32, 0>;
def : ReadAdvance<ReadIDiv, 0>;
def : ReadAdvance<ReadIDiv32, 0>;
def : ReadAdvance<ReadIRem, 0>;
def : ReadAdvance<ReadIRem32, 0>;
def : ReadAdvance<ReadIMul, 0>;
def : ReadAdvance<ReadIMul32, 0>;
def : ReadAdvance<ReadAtomicWA, 0>;
def : ReadAdvance<ReadAtomicWD, 0>;
def : ReadAdvance<ReadAtomicDA, 0>;
def : ReadAdvance<ReadAtomicDD, 0>;
def : ReadAdvance<ReadAtomicLDW, 0>;
def : ReadAdvance<ReadAtomicLDD, 0>;
def : ReadAdvance<ReadAtomicSTW, 0>;
def : ReadAdvance<ReadAtomicSTD, 0>;
def : ReadAdvance<ReadFStoreData, 0>;
def : ReadAdvance<ReadFMemBase, 0>;
def : ReadAdvance<ReadFAdd16, 0>;
def : ReadAdvance<ReadFAdd32, 0>;
def : ReadAdvance<ReadFAdd64, 0>;
def : ReadAdvance<ReadFMul16, 0>;
def : ReadAdvance<ReadFMA16, 0>;
def : ReadAdvance<ReadFMA16Addend, 0>;
def : ReadAdvance<ReadFMul32, 0>;
def : ReadAdvance<ReadFMul64, 0>;
def : ReadAdvance<ReadFMA32, 0>;
def : ReadAdvance<ReadFMA32Addend, 0>;
def : ReadAdvance<ReadFMA64, 0>;
def : ReadAdvance<ReadFMA64Addend, 0>;
def : ReadAdvance<ReadFDiv16, 0>;
def : ReadAdvance<ReadFDiv32, 0>;
def : ReadAdvance<ReadFDiv64, 0>;
def : ReadAdvance<ReadFSqrt16, 0>;
def : ReadAdvance<ReadFSqrt32, 0>;
def : ReadAdvance<ReadFSqrt64, 0>;
def : ReadAdvance<ReadFCmp16, 0>;
def : ReadAdvance<ReadFCmp32, 0>;
def : ReadAdvance<ReadFCmp64, 0>;
def : ReadAdvance<ReadFSGNJ16, 0>;
def : ReadAdvance<ReadFSGNJ32, 0>;
def : ReadAdvance<ReadFSGNJ64, 0>;
def : ReadAdvance<ReadFMinMax16, 0>;
def : ReadAdvance<ReadFMinMax32, 0>;
def : ReadAdvance<ReadFMinMax64, 0>;
def : ReadAdvance<ReadFCvtF16ToI32, 0>;
def : ReadAdvance<ReadFCvtF16ToI64, 0>;
def : ReadAdvance<ReadFCvtF32ToI32, 0>;
def : ReadAdvance<ReadFCvtF32ToI64, 0>;
def : ReadAdvance<ReadFCvtF64ToI32, 0>;
def : ReadAdvance<ReadFCvtF64ToI64, 0>;
def : ReadAdvance<ReadFCvtI32ToF16, 0>;
def : ReadAdvance<ReadFCvtI32ToF32, 0>;
def : ReadAdvance<ReadFCvtI32ToF64, 0>;
def : ReadAdvance<ReadFCvtI64ToF16, 0>;
def : ReadAdvance<ReadFCvtI64ToF32, 0>;
def : ReadAdvance<ReadFCvtI64ToF64, 0>;
def : ReadAdvance<ReadFCvtF32ToF64, 0>;
def : ReadAdvance<ReadFCvtF64ToF32, 0>;
def : ReadAdvance<ReadFCvtF16ToF32, 0>;
def : ReadAdvance<ReadFCvtF32ToF16, 0>;
def : ReadAdvance<ReadFCvtF16ToF64, 0>;
def : ReadAdvance<ReadFCvtF64ToF16, 0>;
def : ReadAdvance<ReadFMovF16ToI16, 0>;
def : ReadAdvance<ReadFMovI16ToF16, 0>;
def : ReadAdvance<ReadFMovF32ToI32, 0>;
def : ReadAdvance<ReadFMovI32ToF32, 0>;
def : ReadAdvance<ReadFMovF64ToI64, 0>;
def : ReadAdvance<ReadFMovI64ToF64, 0>;
def : ReadAdvance<ReadFClass16, 0>;
def : ReadAdvance<ReadFClass32, 0>;
def : ReadAdvance<ReadFClass64, 0>;

// Bitmanip
def : ReadAdvance<ReadRotateImm, 0>;
def : ReadAdvance<ReadRotateImm32, 0>;
def : ReadAdvance<ReadRotateReg, 0>;
def : ReadAdvance<ReadRotateReg32, 0>;
def : ReadAdvance<ReadCLZ, 0>;
def : ReadAdvance<ReadCLZ32, 0>;
def : ReadAdvance<ReadCTZ, 0>;
def : ReadAdvance<ReadCTZ32, 0>;
def : ReadAdvance<ReadCPOP, 0>;
def : ReadAdvance<ReadCPOP32, 0>;
def : ReadAdvance<ReadORCB, 0>;
def : ReadAdvance<ReadIMinMax, 0>;
def : ReadAdvance<ReadREV8, 0>;
def : ReadAdvance<ReadSHXADD, 0>;
def : ReadAdvance<ReadSHXADD32, 0>;
def : ReadAdvance<ReadCLMUL, 0>;
// Single-bit instructions
def : ReadAdvance<ReadSingleBit, 0>;
def : ReadAdvance<ReadSingleBitImm, 0>;

// 6. Configuration-Setting Instructions
def : ReadAdvance<ReadVSETVLI, 0>;
def : ReadAdvance<ReadVSETVL, 0>;

// 7. Vector Loads and Stores
def : ReadAdvance<ReadVLDX, 0>;
def : ReadAdvance<ReadVSTX, 0>;
defm "" : LMULReadAdvance<"ReadVSTEV", 0>;
defm "" : LMULReadAdvance<"ReadVSTM", 0>;
def : ReadAdvance<ReadVLDSX, 0>;
def : ReadAdvance<ReadVSTSX, 0>;
defm "" : LMULReadAdvance<"ReadVSTS8V", 0>;
defm "" : LMULReadAdvance<"ReadVSTS16V", 0>;
defm "" : LMULReadAdvance<"ReadVSTS32V", 0>;
defm "" : LMULReadAdvance<"ReadVSTS64V", 0>;
defm "" : LMULReadAdvance<"ReadVLDUXV", 0>;
defm "" : LMULReadAdvance<"ReadVLDOXV", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX8", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX16", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX32", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX64", 0>;
defm "" : LMULReadAdvance<"ReadVSTUXV", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX8V", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX16V", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX32V", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX64V", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX8", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX16", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX32", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX64", 0>;
defm "" : LMULReadAdvance<"ReadVSTOXV", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX8V", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX16V", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX32V", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX64V", 0>;
// LMUL Aware
def : ReadAdvance<ReadVST1R, 0>;
def : ReadAdvance<ReadVST2R, 0>;
def : ReadAdvance<ReadVST4R, 0>;
def : ReadAdvance<ReadVST8R, 0>;

// 11. Vector Integer Arithmetic Instructions
defm : LMULReadAdvance<"ReadVIALUV", 0>;
defm : LMULReadAdvance<"ReadVIALUX", 0>;
defm : LMULReadAdvanceW<"ReadVIWALUV", 0>;
defm : LMULReadAdvanceW<"ReadVIWALUX", 0>;
defm : LMULReadAdvance<"ReadVExtV", 0>;
defm : LMULReadAdvance<"ReadVICALUV", 0>;
defm : LMULReadAdvance<"ReadVICALUX", 0>;
defm : LMULReadAdvance<"ReadVShiftV", 0>;
defm : LMULReadAdvance<"ReadVShiftX", 0>;
defm : LMULReadAdvanceW<"ReadVNShiftV", 0>;
defm : LMULReadAdvanceW<"ReadVNShiftX", 0>;
defm : LMULReadAdvance<"ReadVICmpV", 0>;
defm : LMULReadAdvance<"ReadVICmpX", 0>;
defm : LMULReadAdvance<"ReadVIMinMaxV", 0>;
defm : LMULReadAdvance<"ReadVIMinMaxX", 0>;
defm : LMULReadAdvance<"ReadVIMulV", 0>;
defm : LMULReadAdvance<"ReadVIMulX", 0>;
defm : LMULSEWReadAdvance<"ReadVIDivV", 0>;
defm : LMULSEWReadAdvance<"ReadVIDivX", 0>;
defm : LMULReadAdvanceW<"ReadVIWMulV", 0>;
defm : LMULReadAdvanceW<"ReadVIWMulX", 0>;
defm : LMULReadAdvance<"ReadVIMulAddV", 0>;
defm : LMULReadAdvance<"ReadVIMulAddX", 0>;
defm : LMULReadAdvanceW<"ReadVIWMulAddV", 0>;
defm : LMULReadAdvanceW<"ReadVIWMulAddX", 0>;
defm : LMULReadAdvance<"ReadVIMergeV", 0>;
defm : LMULReadAdvance<"ReadVIMergeX", 0>;
defm : LMULReadAdvance<"ReadVIMovV", 0>;
defm : LMULReadAdvance<"ReadVIMovX", 0>;

// 12. Vector Fixed-Point Arithmetic Instructions
defm "" : LMULReadAdvance<"ReadVSALUV", 0>;
defm "" : LMULReadAdvance<"ReadVSALUX", 0>;
defm "" : LMULReadAdvance<"ReadVAALUV", 0>;
defm "" : LMULReadAdvance<"ReadVAALUX", 0>;
defm "" : LMULReadAdvance<"ReadVSMulV", 0>;
defm "" : LMULReadAdvance<"ReadVSMulX", 0>;
defm "" : LMULReadAdvance<"ReadVSShiftV", 0>;
defm "" : LMULReadAdvance<"ReadVSShiftX", 0>;
defm "" : LMULReadAdvanceW<"ReadVNClipV", 0>;
defm "" : LMULReadAdvanceW<"ReadVNClipX", 0>;

// 13. Vector Floating-Point Instructions
defm "" : LMULSEWReadAdvanceF<"ReadVFALUV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFALUF", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWALUV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWALUF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMulV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMulF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFDivV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFDivF", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWMulV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWMulF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMulAddV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMulAddF", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWMulAddV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWMulAddF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFSqrtV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFRecpV", 0>;
defm "" : LMULReadAdvance<"ReadVFCmpV", 0>;
defm "" : LMULReadAdvance<"ReadVFCmpF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMinMaxV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMinMaxF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFSgnjV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFSgnjF", 0>;
defm "" : LMULReadAdvance<"ReadVFClassV", 0>;
defm "" : LMULReadAdvance<"ReadVFMergeV", 0>;
defm "" : LMULReadAdvance<"ReadVFMergeF", 0>;
defm "" : LMULReadAdvance<"ReadVFMovF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFCvtIToFV", 0>;
defm "" : LMULReadAdvance<"ReadVFCvtFToIV", 0>;
defm "" : LMULSEWReadAdvanceW<"ReadVFWCvtIToFV", 0>;
defm "" : LMULReadAdvanceFW<"ReadVFWCvtFToIV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWCvtFToFV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFNCvtIToFV", 0>;
defm "" : LMULReadAdvanceW<"ReadVFNCvtFToIV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFNCvtFToFV", 0>;

// 14. Vector Reduction Operations
def : ReadAdvance<ReadVIRedV, 0>;
def : ReadAdvance<ReadVIRedV0, 0>;
def : ReadAdvance<ReadVIWRedV, 0>;
def : ReadAdvance<ReadVIWRedV0, 0>;
def : ReadAdvance<ReadVFRedV, 0>;
def : ReadAdvance<ReadVFRedV0, 0>;
def : ReadAdvance<ReadVFRedOV, 0>;
def : ReadAdvance<ReadVFRedOV0, 0>;
def : ReadAdvance<ReadVFWRedV, 0>;
def : ReadAdvance<ReadVFWRedV0, 0>;
def : ReadAdvance<ReadVFWRedOV, 0>;
def : ReadAdvance<ReadVFWRedOV0, 0>;

// 15. Vector Mask Instructions
defm "" : LMULReadAdvance<"ReadVMALUV", 0>;
defm "" : LMULReadAdvance<"ReadVMPopV", 0>;
defm "" : LMULReadAdvance<"ReadVMFFSV", 0>;
defm "" : LMULReadAdvance<"ReadVMSFSV", 0>;
defm "" : LMULReadAdvance<"ReadVIotaV", 0>;

// 16. Vector Permutation Instructions
def : ReadAdvance<ReadVMovXS, 0>;
def : ReadAdvance<ReadVMovSX_V, 0>;
def : ReadAdvance<ReadVMovSX_X, 0>;
def : ReadAdvance<ReadVMovFS, 0>;
def : ReadAdvance<ReadVMovSF_V, 0>;
def : ReadAdvance<ReadVMovSF_F, 0>;
defm "" : LMULReadAdvance<"ReadVISlideV", 0>;
defm "" : LMULReadAdvance<"ReadVISlideX", 0>;
defm "" : LMULReadAdvance<"ReadVFSlideV", 0>;
defm "" : LMULReadAdvance<"ReadVFSlideF", 0>;
defm "" : LMULSEWReadAdvance<"ReadVRGatherVV_data", 0>;
defm "" : LMULSEWReadAdvance<"ReadVRGatherVV_index", 0>;
defm "" : LMULSEWReadAdvance<"ReadVRGatherEI16VV_data", 0>;
defm "" : LMULSEWReadAdvance<"ReadVRGatherEI16VV_index", 0>;
defm "" : LMULReadAdvance<"ReadVRGatherVX_data", 0>;
defm "" : LMULReadAdvance<"ReadVRGatherVX_index", 0>;
defm "" : LMULReadAdvance<"ReadVRGatherVI_data", 0>;
defm "" : LMULSEWReadAdvance<"ReadVCompressV", 0>;
// LMUL Aware
def : ReadAdvance<ReadVMov1V, 0>;
def : ReadAdvance<ReadVMov2V, 0>;
def : ReadAdvance<ReadVMov4V, 0>;
def : ReadAdvance<ReadVMov8V, 0>;

// Others
def : ReadAdvance<ReadVMask, 0>;
def : ReadAdvance<ReadVPassthru_WorstCase, 0>;
foreach mx = SchedMxList in {
  def : ReadAdvance<!cast<SchedRead>("ReadVPassthru_" # mx), 0>;
  foreach sew = SchedSEWSet<mx>.val in
    def : ReadAdvance<!cast<SchedRead>("ReadVPassthru_" # mx  # "_E" # sew), 0>;
}

//===----------------------------------------------------------------------===//
// Unsupported extensions
defm : UnsupportedSchedQ;
defm : UnsupportedSchedZabha;
defm : UnsupportedSchedZbkb;
defm : UnsupportedSchedZbkx;
defm : UnsupportedSchedZfa;
defm : UnsupportedSchedZvk;
defm : UnsupportedSchedSFB;
defm : UnsupportedSchedXsf;

//===----------------------------------------------------------------------===//
// CompleteModel = 1 formalities: codegen-only pseudos with no SchedRW of
// their own and no UnsupportedFeatures predicate to skip them. Three kinds:
//   (a) generic scalar pseudos (address-materialization, calls/branches,
//       selects, sign-extends, FCSR/FRM bookkeeping) -- most are expanded
//       or custom-inserted before any scheduling, so the values below are
//       never load-bearing; XMDispS with default latency is the honest
//       coarse shape for the few that survive to post-RA;
//   (b) pseudos our rv64imafc_zve32f toolchain can genuinely reach
//       (atomic/cmpxchg expansions, F pseudo-ops, vector spill/reload,
//       vmsge/vmslt expansions) -- coarse but deliberate lane/FU shapes;
//   (c) other targets' unpredicated pseudos (BF16/quarter-float converts,
//       XSfmm tile pseudos, vendor select/CC pseudos) -- unreachable for
//       this target, annotated only to satisfy the completeness check.
let Latency = 1 in
def XMWriteFormalityS : SchedWriteRes<[XMDispS]>;
let Latency = 20, ReleaseAtCycles = [4] in
def XMWriteFormalityAtomic : SchedWriteRes<[XMDispS]>;
let Latency = 4 in
def XMWriteFormalityV : SchedWriteRes<[XMDispV, XMFuSfu]>;
let Latency = 8, ReleaseAtCycles = [1, 4] in
def XMWriteFormalityVLoad : SchedWriteRes<[XMDispV, XMFuLoad]>;
let Latency = 4, ReleaseAtCycles = [1, 4] in
def XMWriteFormalityVStore : SchedWriteRes<[XMDispV, XMFuStore]>;

// (a) generic scalar pseudos.
def : InstRW<[XMWriteFormalityS],
             (instrs ADJCALLSTACKDOWN, ADJCALLSTACKUP, PseudoAddTPRel,
                     PseudoC_ADDI_NOP, PseudoReadVL,
                     HWASAN_CHECK_MEMACCESS_SHORTGRANULES)>;
def : InstRW<[XMWriteFormalityS],
             (instregex "^PseudoBR", "^PseudoCALL", "^PseudoTAIL",
                        "^PseudoRET$", "^PseudoJump$", "^PseudoLL?A",
                        "^PseudoLGA$", "^PseudoLI$", "^Pseudo[SZ]EXT_",
                        "^Select_", "^PseudoCCMOV",
                        "^PseudoL[BHWD]U?$", "^PseudoS[BHWD]$",
                        "^(Clear|Read|Set|Swap|Write)(FCSR|FFLAGS|FRM|VXRM)")>;
// (b) reachable expansions: atomics, F pseudo-ops, vector spill/reload and
// mask-compare expansions.
def : InstRW<[XMWriteFormalityAtomic],
             (instregex "^Pseudo(Masked)?Atomic", "^Pseudo(Masked)?CmpXchg")>;
def : InstRW<[XMWriteFormalityS],
             (instregex "^PseudoF(LW|SW)$", "^PseudoFROUND_S$",
                        "^PseudoQuietFL[ET]_S$")>;
def : InstRW<[XMWriteFormalityVStore], (instregex "^PseudoVSPILL")>;
def : InstRW<[XMWriteFormalityVLoad], (instregex "^PseudoVRELOAD")>;
def : InstRW<[XMWriteFormalityV],
             (instregex "^PseudoVMSGE", "^PseudoVMSLT")>;
// (c) other targets' unpredicated pseudos (unreachable here).
def : InstRW<[XMWriteFormalityV],
             (instregex "^PseudoVF[NW]CVTBF16_", "^PseudoVFNCVT(_SAT)?_F_F(_ALT)?_Q_",
                        "^PseudoSF_")>;

// Custom XMemorable op scheduling info. Task 4 regenerates this file from
// isa/*.yaml (generate_isa.py --sched-td); until then it carries the
// hand-written baseline. Sched annotations target the per-LMUL PSEUDOS
// (PseudoXMV_<OP>_M<X>) for every pseudo-backed op -- the real MC defs never
// reach the scheduler -- and the real defs only for tile.load/tile.store
// (m4-only, no pseudo).
include "RISCVSchedXMemorableInstRW.td"
}
