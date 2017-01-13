From iris.base_logic.lib Require Import namespaces.
From lrust.lang Require Export notation.
From lrust.lang Require Import heap proofmode.
Set Default Proof Using "Type".

Definition memcpy : val :=
  rec: "memcpy" ["dst";"len";"src"] :=
    if: "len" ≤ #0 then #()
    else "dst" <- !"src";;
         "memcpy" ["dst" +ₗ #1 ; "len" - #1 ; "src" +ₗ #1].
Global Opaque memcpy.

Notation "e1 <-{ n } ! e2" :=
  (memcpy (@cons expr e1%E
          (@cons expr (Lit n)
          (@cons expr e2%E nil))))
  (at level 80, n at next level, format "e1  <-{ n }  ! e2") : expr_scope.

Notation "e1 <-{ n ',Σ' i } ! e2" :=
  (e1 <-{Σ i} () ;; e1+ₗ#1 <-{n} !e2)%E
  (at level 80, n, i at next level,
   format "e1  <-{ n ,Σ  i }  ! e2") : expr_scope.

Lemma wp_memcpy `{heapG Σ} E l1 l2 vl1 vl2 q n:
  ↑heapN ⊆ E →
  length vl1 = n → length vl2 = n →
  {{{ heap_ctx ∗ l1 ↦∗ vl1 ∗ l2 ↦∗{q} vl2 }}}
    #l1 <-{n} !#l2 @ E
  {{{ RET #(); l1 ↦∗ vl2 ∗ l2 ↦∗{q} vl2 }}}.
Proof.
  iIntros (? Hvl1 Hvl2 Φ) "(#Hinv & Hl1 & Hl2) HΦ".
  iLöb as "IH" forall (n l1 l2 vl1 vl2 Hvl1 Hvl2). wp_rec. wp_op=> ?; wp_if.
  - iApply "HΦ". assert (n = O) by lia; subst.
    destruct vl1, vl2; try discriminate. by iFrame.
  - destruct vl1 as [|v1 vl1], vl2 as [|v2 vl2], n as [|n]; try discriminate.
    revert Hvl1 Hvl2. intros [= Hvl1] [= Hvl2]; rewrite !heap_mapsto_vec_cons.
    iDestruct "Hl1" as "[Hv1 Hl1]". iDestruct "Hl2" as "[Hv2 Hl2]".
    wp_read; wp_write. replace (Z.pos (Pos.of_succ_nat n)) with (n+1) by lia.
    do 3 wp_op. rewrite Z.add_simpl_r.
    iApply ("IH" with "[%] [%] Hl1 Hl2"); try done.
    iIntros "!> [Hl1 Hl2]"; iApply "HΦ"; by iFrame.
Qed.
