From iris.algebra Require Import gmap auth frac.
From iris.proofmode Require Import tactics.
From lrust.lifetime Require Export lifetime.
Set Default Proof Using "Type".

(** Shared bors  *)
(* TODO : update the TEX with the fact that we can choose the namespace. *)
Definition shr_bor `{invG Σ, lftG Σ} κ N (P : iProp Σ) :=
  (∃ i, &{κ,i}P ∗
    (⌜N ⊥ lftN⌝ ∗ inv N (idx_bor_own 1 i) ∨
     ⌜N = lftN⌝ ∗ inv N (∃ q, idx_bor_own q i)))%I.
Notation "&shr{ κ , N } P" := (shr_bor κ N P)
  (format "&shr{ κ , N }  P", at level 20, right associativity) : uPred_scope.

Section shared_bors.
  Context `{invG Σ, lftG Σ} (P : iProp Σ) (N : namespace).

  Global Instance shr_bor_ne κ n : Proper (dist n ==> dist n) (shr_bor κ N).
  Proof. solve_proper. Qed.
  Global Instance shr_bor_contractive κ : Contractive (shr_bor κ N).
  Proof. solve_contractive. Qed.
  Global Instance shr_bor_proper : Proper ((⊣⊢) ==> (⊣⊢)) (shr_bor κ N).
  Proof. solve_proper. Qed.

  Lemma shr_bor_iff κ P' : ▷ □ (P ↔ P') -∗ &shr{κ, N} P -∗ &shr{κ, N} P'.
  Proof.
    iIntros "HPP' H". iDestruct "H" as (i) "[HP ?]". iExists i. iFrame.
    iApply (idx_bor_iff with "HPP' HP").
  Qed.

  Global Instance shr_bor_persistent : PersistentP (&shr{κ, N} P) := _.

  Lemma bor_share E κ :
    ↑lftN ⊆ E → N = lftN ∨ N ⊥ lftN → &{κ}P ={E}=∗ &shr{κ, N}P.
  Proof.
    iIntros (? HN) "HP". rewrite bor_unfold_idx. iDestruct "HP" as (i) "(#?&Hown)".
    iExists i. iFrame "#". destruct HN as [->|HN].
    - iRight. iSplitR. done. by iMod (inv_alloc with "[Hown]") as "$"; auto.
    - iLeft. iSplitR. done. by iMod (inv_alloc with "[Hown]") as "$"; auto.
  Qed.

  Lemma shr_bor_acc E κ :
    ↑lftN ⊆ E → ↑N ⊆ E →
    lft_ctx -∗ &shr{κ,N}P ={E,E∖↑N∖↑lftN}=∗ ▷P ∗ (▷P ={E∖↑N∖↑lftN,E}=∗ True) ∨
               [†κ] ∗ |={E∖↑N∖↑lftN,E}=> True.
  Proof.
    iIntros (??) "#LFT #HP". iDestruct "HP" as (i) "#[Hidx [[% Hinv]|[% Hinv]]]".
    - iInv N as ">Hi" "Hclose". iMod (idx_bor_atomic_acc with "LFT Hidx Hi")
        as "[[HP Hclose']|[H† Hclose']]". solve_ndisj.
      + iLeft. iFrame. iIntros "!>HP". iMod ("Hclose'" with "HP"). by iApply "Hclose".
      + iRight. iFrame. iIntros "!>". iMod "Hclose'". by iApply "Hclose".
    - subst. rewrite difference_twice_L. iInv lftN as (q') ">[Hq'0 Hq'1]" "Hclose".
      iMod ("Hclose" with "[Hq'1]") as "_". by eauto.
      iMod (idx_bor_atomic_acc with "LFT Hidx Hq'0") as "[[HP Hclose]|[H† Hclose]]". done.
      + iLeft. iFrame. iIntros "!>HP". by iMod ("Hclose" with "HP").
      + iRight. iFrame. iIntros "!>". by iMod "Hclose".
  Qed.

  Lemma shr_bor_acc_tok E q κ :
    ↑lftN ⊆ E → ↑N ⊆ E →
    lft_ctx -∗ &shr{κ,N}P -∗ q.[κ] ={E,E∖↑N}=∗ ▷P ∗ (▷P ={E∖↑N,E}=∗ q.[κ]).
  Proof.
    iIntros (??) "#LFT #HP Hκ". iDestruct "HP" as (i) "#[Hidx [[% Hinv]|[% Hinv]]]".
    - iInv N as ">Hi" "Hclose".
      iMod (idx_bor_acc with "LFT Hidx Hi Hκ") as "[$ Hclose']". solve_ndisj.
      iIntros "!> H". iMod ("Hclose'" with "H") as "[? $]". by iApply "Hclose".
    - iMod (shr_bor_acc with "LFT []") as "[[$ Hclose]|[H† _]]"; try done.
      + iExists i. auto.
      + subst. rewrite difference_twice_L. iIntros "!>HP". by iMod ("Hclose" with "HP").
      + iDestruct (lft_tok_dead with "Hκ H†") as "[]".
  Qed.

  Lemma shr_bor_shorten κ κ': κ ⊑ κ' -∗ &shr{κ',N}P -∗ &shr{κ,N}P.
  Proof.
    iIntros "#H⊑ H". iDestruct "H" as (i) "[??]". iExists i. iFrame.
      by iApply (idx_bor_shorten with "H⊑").
  Qed.

  Lemma shr_bor_fake E κ:
    ↑lftN ⊆ E → N = lftN ∨ N ⊥ lftN → lft_ctx -∗ [†κ] ={E}=∗ &shr{κ,N}P.
  Proof.
    iIntros (??) "#LFT#H†". iApply (bor_share with ">"); try done.
    by iApply (bor_fake with "LFT H†").
  Qed.
End shared_bors.

Typeclasses Opaque shr_bor.
