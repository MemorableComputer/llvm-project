//===-- RISCVInstrInfoXMemorable.td --------------------------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file describes the Memorable decode-engine custom vector extension
// (Xmemorable). It is the single home for all Xmemorable instruction, operand,
// and pattern definitions added in later tasks.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Encoding classes
//===----------------------------------------------------------------------===//

// CUSTOM1V (isa/vector.yaml): custom-1 vector-engine ops, funct3=0b001,
// funct6 in Inst{31-26}, mode bit in Inst{25}. asm map vd->[11:7],
// va(vs1)->[19:15], vb(vs2)->[24:20].
class XMVCustom1V<bits<6> funct6, bits<1> mode, dag outs, dag ins,
                  string opcodestr, string argstr>
    : RVInst<outs, ins, opcodestr, argstr, [], InstFormatR> {
  bits<5> vs2;  bits<5> vs1;  bits<5> vd;
  let Inst{31-26} = funct6;
  let Inst{25}    = mode;
  let Inst{24-20} = vs2;
  let Inst{19-15} = vs1;
  let Inst{14-12} = 0b001;
  let Inst{11-7}  = vd;
  let Inst{6-0}   = 0b0101011;
}

// CUSTOM1 (isa/vector.yaml): custom-1 scalar-operand ops (e.g. tile.load),
// funct3=0b000, funct7 in Inst{31-25}, rs2 field Inst{24-20} = 0 (unused),
// rs1->[19:15], vd->[11:7]. Distinct from XMVCustom1V above (funct3=0b001,
// vector vs1/vs2 operands) — Task 8 reuses this class.
class XMVCustom1<bits<7> funct7, dag outs, dag ins,
                 string opcodestr, string argstr>
    : RVInst<outs, ins, opcodestr, argstr, [], InstFormatR> {
  bits<5> rs1;  bits<5> vd;
  let Inst{31-25} = funct7;
  let Inst{24-20} = 0b00000;
  let Inst{19-15} = rs1;
  let Inst{14-12} = 0b000;
  let Inst{11-7}  = vd;
  let Inst{6-0}   = 0b0101011;
}

// CUSTOM1R4 (isa/matrix.yaml): custom-1 matrix multiply-family ops,
// funct3=0b010, R4-type (four register fields), funct2 in Inst{26-25}
// selects the family member. rd is a SOURCE (the descriptor), never
// written -- asm map: rd=desc, rs1=rsA, rs2=rsB, rs3=rsC (dest tile addr;
// reserved 0 on matrix.multiply, which has no rsC operand).
class XMVCustom1R4<bits<2> funct2, dag outs, dag ins,
                   string opcodestr, string argstr>
    : RVInst<outs, ins, opcodestr, argstr, [], InstFormatR4> {
  bits<5> rs3;  bits<5> rs2;  bits<5> rs1;  bits<5> rd;
  let Inst{31-27} = rs3;
  let Inst{26-25} = funct2;
  let Inst{24-20} = rs2;
  let Inst{19-15} = rs1;
  let Inst{14-12} = 0b010;
  let Inst{11-7}  = rd;
  let Inst{6-0}   = 0b0101011;
}

// XMVCustom0R (isa/custom.yaml): custom-0 (0x0b) scalar R-type ops -- the
// one Xmemorable-backend op outside the custom-1 vector-engine block. Standard
// R-type GPR fields (rd/rs1/rs2); funct3 selects the family, funct7 the
// member within it (cmul today: funct3=0, funct7=0).
class XMVCustom0R<bits<3> funct3, bits<7> funct7, dag outs, dag ins,
                  string opcodestr, string argstr>
    : RVInst<outs, ins, opcodestr, argstr, [], InstFormatR> {
  bits<5> rs2;  bits<5> rs1;  bits<5> rd;
  let Inst{31-25} = funct7;
  let Inst{24-20} = rs2;
  let Inst{19-15} = rs1;
  let Inst{14-12} = funct3;
  let Inst{11-7}  = rd;
  let Inst{6-0}   = 0b0001011;
}

//===----------------------------------------------------------------------===//
// Instructions
//===----------------------------------------------------------------------===//

// NOTE: deliberately NOT wrapped in `let DecoderNamespace = "XMemorable"`.
// Tried it (per the XCV/XAndes/XSpacemiT/Xqci custom-1 convention) and it
// broke the vexp2diff.vv disassembler round-trip (llvm-objdump printed
// `<unknown>` instead of the mnemonic): a new DecoderNamespace needs a new
// entry in the C++ table-dispatch array in RISCVDisassembler.cpp (see
// e.g. DecoderTableXCV32/XqciFeatureGroup there) — .td alone can't wire
// it up. Per task instructions, reverted rather than add C++; instructions
// stay in the default namespace, same as before this task.
// cmul (isa/custom.yaml): custom-0 (0x0b) scalar op, R-type, funct3=0,
// funct7=0 -- rd = complex-multiply(rs1, rs2), a pure GPR-to-GPR function
// (IntrNoMem). The only Xmemorable-backend op outside the custom-1
// vector-engine block; VL/VTYPE are irrelevant to it (see the Uses
// computation above).
let Predicates = [HasVendorXMemorable],
    hasSideEffects = 0, mayLoad = 0, mayStore = 0 in
def XMV_CMUL : XMVCustom0R<0x0, 0x0, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
      "cmul", "$rd, $rs1, $rs2">;

// Hidden-state ops (task 8, findings §6 as revised by PR #21): these are
// the accepted-wall ops -- side-effecting by design, no MMO path, state
// (TBUF/MACC) the compiler cannot otherwise see. Instruction-side flags
// measured to be required by TableGen's consistency check for an
// [IntrHasSideEffects] intrinsic with no MMO-bearing Pat: hasSideEffects=1,
// mayLoad=1, mayStore=1 on all three ops (see NOTES.md for the trace).

// vappend (isa/vector.yaml): rs1 only, rd/vs2 fields unused (hardcoded 0).
// Reads mem BUT writes TBUF -- exactly the op where IntrReadMem would look
// right on the intrinsic side and silently miscompile (see the intrinsic
// comment); mirrored here by NOT giving this instruction a load Pat/MMO.
let Predicates = [HasVendorXMemorable], Defs = [TBUF], Uses = [TBUF, VL, VTYPE],
    hasSideEffects = 1, mayLoad = 1, mayStore = 1 in
def XMV_VAPPEND : XMVCustom1V<0x00, 0, (outs), (ins GPR:$vs1),
      "vappend", "$vs1"> {
  let vs2 = 0;
  let vd  = 0;
}

// store.transposed (isa/vector.yaml): "vs, rs1" with vs (the transpose-
// buffer column index, a plain immediate -- not a vector register) riding
// the vd field per the yaml asm map; vs2 unused (hardcoded 0).
let Predicates = [HasVendorXMemorable], Defs = [TBUF], Uses = [TBUF, VL, VTYPE],
    hasSideEffects = 1, mayLoad = 1, mayStore = 1 in
def XMV_STORE_TRANSPOSED : XMVCustom1V<0x01, 0,
      (outs), (ins uimm5:$vd, GPR:$vs1),
      "store.transposed", "$vd, $vs1"> {
  let vs2 = 0;
}

// store.int4.e8m0 (isa/vector.yaml): the per-column int4 quantize-store.
// vd field carries the SOURCE vreg per the yaml asm map (vs->[11:7]);
// vs1/vs2 carry the data addr / scale-bank addr. This MC def is the
// canonical asm/decode form; codegen reaches it through the per-LMUL
// pseudo family below (the old m1-only store_databank fusion is retired
// -- see the framework section).
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 1, hasNoSchedulingInfo = 1 in
def XMV_STORE_INT4_E8M0 : XMVCustom1V<0x02, 0,
      (outs), (ins VR:$vd, GPR:$vs1, GPR:$vs2),
      "store.int4.e8m0", "$vd, $vs1, $vs2">;

// store.int4.e4m3 (isa/vector.yaml): same quantize-store shape as
// store.int4.e8m0 above, E4M3 block-scale variant.
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 1, hasNoSchedulingInfo = 1 in
def XMV_STORE_INT4_E4M3 : XMVCustom1V<0x03, 0,
      (outs), (ins VR:$vd, GPR:$vs1, GPR:$vs2),
      "store.int4.e4m3", "$vd, $vs1, $vs2">;

// store.int4.e8m3 (isa/vector.yaml): same quantize-store shape as
// store.int4.e8m0 above, E8M3 block-scale variant.
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 1, hasNoSchedulingInfo = 1 in
def XMV_STORE_INT4_E8M3 : XMVCustom1V<0x04, 0,
      (outs), (ins VR:$vd, GPR:$vs1, GPR:$vs2),
      "store.int4.e8m3", "$vd, $vs1, $vs2">;

let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 0, hasNoSchedulingInfo = 1 in
def XMV_VEXP2DIFF_VV : XMVCustom1V<0x05, 0,
      (outs VR:$vd), (ins VR:$vs1, VR:$vs2),
      "vexp2diff.vv", "$vd, $vs1, $vs2">;

// vexp2diff.fx (isa/vector.yaml): same CUSTOM1V shape as vexp2diff.vv
// above (funct6=0x06), but its RESULT is an unsigned Q16.16 fixed-point
// value in a same-LMUL i32 lane, not FP32 (isa/vector.yaml's result_type
// override) -- see XMVPatBinaryVFx/XMVFxTypePairs in the framework
// section; the register class (VR) and both operand types are unchanged.
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 0, hasNoSchedulingInfo = 1 in
def XMV_VEXP2DIFF_FX : XMVCustom1V<0x06, 0,
      (outs VR:$vd), (ins VR:$vs1, VR:$vs2),
      "vexp2diff.fx", "$vd, $vs1, $vs2">;

let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 1, mayStore = 0 in
def XMV_TILE_LOAD : XMVCustom1<0x3, (outs VRM4:$vd), (ins GPR:$rs1),
                               "tile.load", "$vd, $rs1">;

// tile.store (isa/vector.yaml): "vs, rs1" with vs (the row-group SOURCE,
// not a destination) riding the vd field per the yaml asm map -- the
// store-direction twin of tile.load above (also no standalone intrinsic; a
// bare IR `store` of <vscale x 8 x float> to addrspace(1) selects this via
// the store_tile PatFrag in the Patterns section below).
let Predicates = [HasVendorXMemorable], Uses = [VL, VTYPE],
    hasSideEffects = 0, mayLoad = 0, mayStore = 1 in
def XMV_TILE_STORE : XMVCustom1<0x4, (outs), (ins VRM4:$vd, GPR:$rs1),
                               "tile.store", "$vd, $rs1">;

// matrix.multiply_drain (isa/matrix.yaml): R4-type, all-GPR operands
// including rd (the descriptor, a SOURCE -- never written); opcode 0x2b,
// funct3=0b010, funct2=0x0 (match 0x0000202b).
let Predicates = [HasVendorXMemorable], Defs = [MACC], Uses = [MACC],
    hasSideEffects = 1, mayLoad = 1, mayStore = 1 in
def XMV_MATRIX_MULTIPLY_DRAIN : XMVCustom1R4<0x0,
      (outs), (ins GPR:$rd, GPR:$rs1, GPR:$rs2, GPR:$rs3),
      "matrix.multiply_drain", "$rd, $rs1, $rs2, $rs3">;

//===----------------------------------------------------------------------===//
// LMUL pseudo framework (upstream-style; see the header note)
//===----------------------------------------------------------------------===//

// Whole LMULs only: fractional vlmul is RESERVED on this machine (vsetvli
// sets vill -- isa/vector.yaml), so an mf-typed surface could only trap.
defvar MxListXMV = [V_M1, V_M2, V_M4, V_M8];
defvar XMVF32Vectors = [VF32M1, VF32M2, VF32M4, VF32M8];

// f32 operand type -> the same-LMUL i32 result type (vexp2diff.fx's
// unsigned Q16.16 lanes -- isa/vector.yaml's result_type override).
class XMVFxTypePair<VTypeInfo f, VTypeInfo i> {
  VTypeInfo Fti = f;
  VTypeInfo Iti = i;
}
defvar XMVFxTypePairs = [XMVFxTypePair<VF32M1, VI32M1>,
                         XMVFxTypePair<VF32M2, VI32M2>,
                         XMVFxTypePair<VF32M4, VI32M4>,
                         XMVFxTypePair<VF32M8, VI32M8>];

// Per-LMUL pseudos for a vd = op(vs1, vs2) value op: upstream's own
// VPseudoBinaryNoMask (rd; rs2, rs1, avl, sew -- no passthru/mask: this
// machine has no mask support, and the ops' tail handling is the ISS
// contract's own, not policy-selected). BaseInstr is passed EXPLICITLY
// everywhere in this file: RISCVVPseudo's default PseudoToVInst
// name-stripping would corrupt base names containing "_E8"
// (store.int4.e8m0/e8m3 -> its AffixSubsts strip "_E8"), so relying on it
// for SOME ops and not others would be a trap; uniform explicitness is
// the fix.
multiclass XMVPseudoBinaryV<string base> {
  foreach m = MxListXMV in {
    let VLMul = m.value, BaseInstr = !cast<Instruction>(base) in
    def "_" # m.MX : VPseudoBinaryNoMask<m.vrclass, m.vrclass, m.vrclass, "">;
  }
}

// Per-LMUL pseudos for the grouped quantize-store (vs, data, scale): void
// and DIRECTLY side-effecting -- vl/16 adjacent micro-blocks have no
// single-i64-store/MMO model, so there is no store fusion at ANY LMUL
// under the framework (the old m1 store_databank fusion is retired).
// hasSideEffects/mayLoad/mayStore = 1/1/1: the measured no-MMO
// [IntrHasSideEffects] requirement (same rule as the state trio; see
// NOTES.md).
class XMVPseudoStoreInt4NoMask<VReg SrcClass>
    : RISCVVPseudo<(outs),
                   (ins SrcClass:$vs, GPR:$rs1, GPR:$rs2, AVL:$vl, sew:$sew)> {
  let mayLoad = 1;
  let mayStore = 1;
  let hasSideEffects = 1;
  let HasVLOp = 1;
  let HasSEWOp = 1;
}

multiclass XMVPseudoStoreInt4<string base> {
  foreach m = MxListXMV in {
    let VLMul = m.value, BaseInstr = !cast<Instruction>(base) in
    def "_" # m.MX : XMVPseudoStoreInt4NoMask<m.vrclass>;
  }
}

// Selection: (intrinsic op1, op2, vl) -> (pseudo op1, op2, vl, sew) --
// upstream's VPatBinaryM shape, folded over the type list so all-LMUL
// coverage falls out of the one polymorphic intrinsic.
multiclass XMVPatBinaryV<string intrinsic, string inst> {
  foreach vti = XMVF32Vectors in
    let Predicates = !listconcat(GetVTypePredicates<vti>.Predicates,
                                 [HasVendorXMemorable]) in
    def : VPatBinaryM<intrinsic, inst # "_" # vti.LMul.MX,
                      vti.Vector, vti.Vector, vti.Vector,
                      vti.Log2SEW, vti.RegClass, vti.RegClass>;
}

multiclass XMVPatBinaryVFx<string intrinsic, string inst> {
  foreach p = XMVFxTypePairs in
    let Predicates = !listconcat(GetVTypePredicates<p.Fti>.Predicates,
                                 [HasVendorXMemorable]) in
    def : VPatBinaryM<intrinsic, inst # "_" # p.Fti.LMul.MX,
                      p.Iti.Vector, p.Fti.Vector, p.Fti.Vector,
                      p.Fti.Log2SEW, p.Fti.RegClass, p.Fti.RegClass>;
}

class XMVPatStoreInt4Base<string intrinsic, string inst, VTypeInfo vti>
    : Pat<(!cast<Intrinsic>(intrinsic)
              (vti.Vector vti.RegClass:$vs), GPR:$rs1, GPR:$rs2, VLOpFrag),
          (!cast<Instruction>(inst # "_" # vti.LMul.MX)
              vti.RegClass:$vs, GPR:$rs1, GPR:$rs2, GPR:$vl, vti.Log2SEW)>;

multiclass XMVPatStoreInt4<string intrinsic, string inst> {
  foreach vti = XMVF32Vectors in
    let Predicates = !listconcat(GetVTypePredicates<vti>.Predicates,
                                 [HasVendorXMemorable]) in
    def : XMVPatStoreInt4Base<intrinsic, inst, vti>;
}

let Predicates = [HasVendorXMemorable] in {
defm PseudoXMV_STORE_INT4_E8M0 : XMVPseudoStoreInt4<"XMV_STORE_INT4_E8M0">;
defm PseudoXMV_STORE_INT4_E4M3 : XMVPseudoStoreInt4<"XMV_STORE_INT4_E4M3">;
defm PseudoXMV_STORE_INT4_E8M3 : XMVPseudoStoreInt4<"XMV_STORE_INT4_E8M3">;
defm PseudoXMV_VEXP2DIFF_VV : XMVPseudoBinaryV<"XMV_VEXP2DIFF_VV">;
defm PseudoXMV_VEXP2DIFF_FX : XMVPseudoBinaryV<"XMV_VEXP2DIFF_FX">;
} // Predicates = [HasVendorXMemorable]

//===----------------------------------------------------------------------===//
// Patterns
//===----------------------------------------------------------------------===//

def : Pat<(i64 (int_riscv_memorable_cmul GPR:$rs1, GPR:$rs2)),
          (XMV_CMUL GPR:$rs1, GPR:$rs2)>;

// Hidden-state ops (task 8): straight intrinsic -> instruction Pats, no
// MMO/fusion involved -- these are the accepted-wall ops (findings §5).
def : Pat<(int_riscv_memorable_vappend GPR:$vs1), (XMV_VAPPEND GPR:$vs1)>;

// ImmArg lowers the column operand to ISD::TargetConstant (timm), not
// ISD::Constant (imm) -- uimm5 is an ImmLeaf (matches imm only), so a bare
// `uimm5:$vd` (or bare `timm:$vd`, which carries NO range predicate at
// all) on the LHS either fails to match altogether or -- the bare-`timm`
// case, measured -- silently accepts and truncates an out-of-range column
// (e.g. intrinsic column 35 compiled to `store.transposed 35, a0` in the
// asm printer's operand text but encoded 35 & 0x1f = 3 in the actual
// instruction word, no diagnostic at all; m1/store_transposed_oob.ll is
// the pinned regression test for this). `xmv_uimm5_timm` restores the
// range check on the timm path (mirrors uimm5's own `isUInt<5>` predicate,
// just against the timm node instead of imm). RHS also spelled with the
// same `xmv_uimm5_timm` class (not bare `uimm5`) -- retyping the RHS to a
// *different* operand-class record than the LHS crashed llvm-tblgen's
// GlobalISel emitter (segfault in
// CopyConstantAsImmRenderer::emitRenderOpcodes while auto-importing a
// LHS-timm/RHS-uimm5 Pat); using the identical class on both sides avoids
// the mismatch and does not reintroduce the crash (verified).
def xmv_uimm5_timm : TImmLeaf<i64, [{return isUInt<5>(Imm);}]>;
def : Pat<(int_riscv_memorable_store_transposed xmv_uimm5_timm:$vd, GPR:$vs1),
          (XMV_STORE_TRANSPOSED xmv_uimm5_timm:$vd, GPR:$vs1)>;

defm : XMVPatStoreInt4<"int_riscv_memorable_int4_quantize_e8m0", "PseudoXMV_STORE_INT4_E8M0">;

defm : XMVPatStoreInt4<"int_riscv_memorable_int4_quantize_e4m3", "PseudoXMV_STORE_INT4_E4M3">;

defm : XMVPatStoreInt4<"int_riscv_memorable_int4_quantize_e8m3", "PseudoXMV_STORE_INT4_E8M3">;

defm : XMVPatBinaryV<"int_riscv_memorable_vexp2diff_vv", "PseudoXMV_VEXP2DIFF_VV">;

defm : XMVPatBinaryVFx<"int_riscv_memorable_vexp2diff_fx", "PseudoXMV_VEXP2DIFF_FX">;

def load_tile : PatFrag<(ops node:$ptr), (load node:$ptr)> {
  let IsLoad = true;
  let AddressSpaces = [1];
}
let AddedComplexity = 20 in
def : Pat<(nxv8f32 (load_tile GPR:$rs1)), (XMV_TILE_LOAD GPR:$rs1)>;

// tile.store: the store-direction twin of tile.load's load_tile PatFrag
// above -- same AddedComplexity race (a plain scalar/vector store pattern
// can out-rank a custom one here), same fix.
def store_tile : PatFrag<(ops node:$val, node:$ptr), (store node:$val, node:$ptr)> {
  let IsStore = true;
  let AddressSpaces = [1];
}
let AddedComplexity = 20 in
def : Pat<(store_tile (nxv8f32 VRM4:$vd), GPR:$rs1),
          (XMV_TILE_STORE VRM4:$vd, GPR:$rs1)>;

def : Pat<(int_riscv_memorable_matrix_multiply_drain
              GPR:$rd, GPR:$rs1, GPR:$rs2, GPR:$rs3),
          (XMV_MATRIX_MULTIPLY_DRAIN GPR:$rd, GPR:$rs1, GPR:$rs2, GPR:$rs3)>;
