; Sched-model gate for the xmemorable node's 3-lane dispatch (sched-model
; task 3, RISCVSchedXMemorable.td): the xmemorable-node tune CPU must
; exist and select XMemorableModel, and codegen through the complete
; model (CompleteModel = 1) must still lower the custom per-LMUL pseudos.
;
; NOTE llc, not %clang: the release-gate lit config is a bare ShTest with
; no substitutions (see the workflow's scratch lit.cfg), the same contract
; as the generated tests in this directory. And the tune CPU rides the
; "tune-cpu" FUNCTION ATTRIBUTE below (clang -mtune's own encoding, read
; by RISCVTargetMachine), NOT -mcpu: llc has no -mtune, and a tune-only
; processor def carries no ISA features, so -mcpu=xmemorable-node dies
; with "RV64 target requires an RV64 CPU" (measured, CI run 31218687641).
;
; An unknown tune-cpu is only a WARNING that silently falls back to
; generic scheduling, so the first RUN pins the tune CPU's existence by
; requiring an empty stderr-side warning stream; the second checks
; codegen on stdout. The WARN-NOT anchor is the QUOTED CPU NAME, not the
; diagnostic's prose: every MCSubtargetInfo unknown-CPU path prints
; 'xmemorable-node' (quoted) before its message, so the pin survives an
; upstream rewording of "... is not a recognized processor ..." while
; still tripping whenever the tune CPU is missing (red case demonstrated
; on the snapshot llc; see task-3 report).
;
; RUN: llc -mtriple=riscv64 -mattr=+m,+zve32f,+zvl512b,+xmemorable \
; RUN:   -O2 %s -o /dev/null 2>&1 | FileCheck --allow-empty --check-prefix=WARN %s
; RUN: llc -mtriple=riscv64 -mattr=+m,+zve32f,+zvl512b,+xmemorable \
; RUN:   -O2 %s -o - | FileCheck %s
;
; WARN-NOT: 'xmemorable-node'

; Loop body: two independent m1 vexp2diff calls (operands are loop phis)
; plus independent scalar counter bumps. Deliberately NOT asserting a
; particular interleave shape: on this kernel the register allocator
; WAR-chains the two vector ops through v8/v9, and the first CI landing
; (run 31220272328) showed the in-order scheduler legitimately emitting
; them back-to-back with the scalar work behind -- pinning instruction
; order here would gate on scheduler heuristics, not on the model
; contract. The measurable interleaving claim belongs to the static
; lane-adjacency gate over real kernel disassembly (design Sec 4 item 2,
; Task 7) and the btb pipe-log measurement (Sec 4 item 3).
; TODO(task 7): point the lane-adjacency checker at this model's output.

define <vscale x 2 x float> @tune_cpu_exists_and_lowers(<vscale x 2 x float> %a, <vscale x 2 x float> %b, i64 %n, ptr %p) #0 {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %s1 = phi i64 [ 0, %entry ], [ %s1.next, %loop ]
  %s2 = phi i64 [ 0, %entry ], [ %s2.next, %loop ]
  %s3 = phi i64 [ 0, %entry ], [ %s3.next, %loop ]
  %s4 = phi i64 [ 0, %entry ], [ %s4.next, %loop ]
  %va = phi <vscale x 2 x float> [ %a, %entry ], [ %r1, %loop ]
  %vb = phi <vscale x 2 x float> [ %b, %entry ], [ %r2, %loop ]
  %s1.next = add i64 %s1, %i
  %s2.next = add i64 %s2, 3
  %s3.next = add i64 %s3, %i
  %s4.next = add i64 %s4, 7
  %r1 = call <vscale x 2 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv2f32.i64(<vscale x 2 x float> %va, <vscale x 2 x float> %vb, i64 16)
  %r2 = call <vscale x 2 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv2f32.i64(<vscale x 2 x float> %vb, <vscale x 2 x float> %va, i64 16)
  %i.next = add i64 %i, 1
  %cond = icmp ult i64 %i.next, %n
  br i1 %cond, label %loop, label %exit

exit:
  %sa = add i64 %s1.next, %s2.next
  %sb = add i64 %s3.next, %s4.next
  %sc = add i64 %sa, %sb
  store i64 %sc, ptr %p
  ret <vscale x 2 x float> %r2
}

declare <vscale x 2 x float> @llvm.riscv.memorable.vexp2diff.vv.nxv2f32.i64(<vscale x 2 x float>, <vscale x 2 x float>, i64)

attributes #0 = { "tune-cpu"="xmemorable-node" }

; Codegen under XMemorableModel: vtype management and pseudo->real
; lowering intact for both calls (CompleteModel would have failed the
; toolchain build itself on any sched-info gap for what this function
; emits).
; CHECK: {{vsetivli|vsetvli}} {{.*}}e32, m1,
; CHECK: vexp2diff.vv
; CHECK: vexp2diff.vv
