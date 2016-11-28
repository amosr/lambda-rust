From iris.algebra Require Import csum auth frac gmap dec_agree gset.
From iris.prelude Require Export gmultiset strings.
From iris.base_logic.lib Require Export invariants.
From iris.base_logic.lib Require Import boxes.
From iris.base_logic Require Import big_op.
Import uPred.

Definition lftN : namespace := nroot .@ "lft".
Definition borN : namespace := lftN .@ "bor".
Definition inhN : namespace := lftN .@ "inh".
Definition mgmtN : namespace := lftN .@ "mgmt".

Definition atomic_lft := positive.
Notation lft := (gmultiset positive).
Definition static : lft := ∅.

Inductive bor_state :=
  | Bor_in
  | Bor_open (q : frac)
  | Bor_rebor (κ : lft).
Instance bor_state_eq_dec : EqDecision bor_state.
Proof. solve_decision. Defined.

Definition bor_filled (s : bor_state) : bool :=
  match s with Bor_in => true | _ => false end.

Definition lft_stateR := csumR fracR unitR.
Definition to_lft_stateR (b : bool) : lft_stateR :=
  if b then Cinl 1%Qp else Cinr ().

Record lft_names := LftNames {
  bor_name : gname;
  cnt_name : gname;
  inh_name : gname
}.
Instance lft_names_eq_dec : EqDecision lft_names.
Proof. solve_decision. Defined.

Definition alftUR := gmapUR atomic_lft lft_stateR.
Definition to_alftUR : gmap atomic_lft bool → alftUR := fmap to_lft_stateR.

Definition ilftUR := gmapUR lft (dec_agreeR lft_names).
Definition to_ilftUR : gmap lft lft_names → ilftUR := fmap DecAgree.

Definition borUR := gmapUR slice_name (prodR fracR (dec_agreeR bor_state)).
Definition to_borUR : gmap slice_name bor_state → borUR := fmap ((1%Qp,) ∘ DecAgree).

Definition inhUR := gset_disjUR slice_name.

Class lftG Σ := LftG {
  lft_box :> boxG Σ;
  alft_inG :> inG Σ (authR alftUR);
  alft_name : gname;
  ilft_inG :> inG Σ (authR ilftUR);
  ilft_name : gname;
  lft_bor_box :> inG Σ (authR borUR);
  lft_cnt_inG :> inG Σ (authR natUR);
  lft_inh_box :> inG Σ (authR inhUR);
}.

Section defs.
  Context `{invG Σ, lftG Σ}.

  Definition lft_tok (q : Qp) (κ : lft) : iProp Σ :=
    ([∗ mset] Λ ∈ κ, own alft_name (◯ {[ Λ := Cinl q ]}))%I.

  Definition lft_dead (κ : lft) : iProp Σ :=
    (∃ Λ, ⌜Λ ∈ κ⌝ ∗ own alft_name (◯ {[ Λ := Cinr () ]}))%I.

  Definition own_alft_auth (A : gmap atomic_lft bool) : iProp Σ :=
    own alft_name (● to_alftUR A).
  Definition own_ilft_auth (I : gmap lft lft_names) : iProp Σ :=
    own ilft_name (● to_ilftUR I).

  Definition own_bor (κ : lft)
      (x : auth (gmap slice_name (frac * dec_agree bor_state))) : iProp Σ :=
    (∃ γs,
      own ilft_name (◯ {[ κ := DecAgree γs ]}) ∗
      own (bor_name γs) x)%I.

  Definition own_cnt (κ : lft) (x : auth nat) : iProp Σ :=
    (∃ γs,
      own ilft_name (◯ {[ κ := DecAgree γs ]}) ∗
      own (cnt_name γs) x)%I.

  Definition own_inh (κ : lft) (x : auth (gset_disj slice_name)) : iProp Σ :=
    (∃ γs,
      own ilft_name (◯ {[ κ := DecAgree γs ]}) ∗
      own (inh_name γs) x)%I.

  Definition bor_cnt (κ : lft) (s : bor_state) : iProp Σ :=
    match s with
    | Bor_in => True
    | Bor_open q => lft_tok q κ
    | Bor_rebor κ' => ⌜κ ⊂ κ'⌝ ∗ own_cnt κ' (◯ 1)
    end%I.

  Definition lft_bor_alive (κ : lft) (Pi : iProp Σ) : iProp Σ :=
    (∃ B : gmap slice_name bor_state,
      box borN (bor_filled <$> B) Pi ∗
      own_bor κ (● to_borUR B) ∗
      [∗ map] s ∈ B, bor_cnt κ s)%I.

  Definition lft_bor_dead (κ : lft) : iProp Σ :=
     (∃ (B: gset slice_name) (Pb : iProp Σ),
       own_bor κ (● to_gmap (1%Qp, DecAgree Bor_in) B) ∗
       box borN (to_gmap false B) Pb)%I.

   Definition lft_inh (κ : lft) (s : bool) (Pi : iProp Σ) : iProp Σ :=
     (∃ E : gset slice_name,
       own_inh κ (● GSet E) ∗
       box inhN (to_gmap s E) Pi)%I.

   Definition lft_vs_inv_go (κ : lft) (lft_inv_alive : ∀ κ', κ' ⊂ κ → iProp Σ)
       (I : gmap lft lft_names) : iProp Σ :=
     (lft_bor_dead κ ∗
       own_ilft_auth I ∗
       [∗ set] κ' ∈ dom _ I, ∀ Hκ : κ' ⊂ κ, lft_inv_alive κ' Hκ)%I.

   Definition lft_vs_go (κ : lft) (lft_inv_alive : ∀ κ', κ' ⊂ κ → iProp Σ)
       (Pb Pi : iProp Σ) : iProp Σ :=
     (∃ n : nat,
       own_cnt κ (● n) ∗
       ∀ I : gmap lft lft_names,
         lft_vs_inv_go κ lft_inv_alive I -∗ ▷ Pb -∗ lft_dead κ
           ={⊤∖↑mgmtN}=∗
         lft_vs_inv_go κ lft_inv_alive I ∗ ▷ Pi ∗ own_cnt κ (◯ n))%I.

  Definition lft_inv_alive_go (κ : lft)
      (lft_inv_alive : ∀ κ', κ' ⊂ κ → iProp Σ) : iProp Σ :=
    (∃ Pb Pi,
      lft_bor_alive κ Pb ∗
      lft_vs_go κ lft_inv_alive Pb Pi ∗
      lft_inh κ false Pi)%I.

  Definition lft_inv_alive (κ : lft) : iProp Σ :=
    Fix_F _ lft_inv_alive_go (gmultiset_wf κ).
  Definition lft_vs_inv (κ : lft) (I : gmap lft lft_names) : iProp Σ :=
    lft_vs_inv_go κ (λ κ' _, lft_inv_alive κ') I.
  Definition lft_vs (κ : lft) (Pb Pi : iProp Σ) : iProp Σ :=
    lft_vs_go κ (λ κ' _, lft_inv_alive κ') Pb Pi.

  Definition lft_inv_dead (κ : lft) : iProp Σ :=
    (∃ Pi,
      lft_bor_dead κ ∗
      own_cnt κ (● 0) ∗
      lft_inh κ true Pi)%I.

  Definition lft_alive_in (A : gmap atomic_lft bool) (κ : lft) : Prop :=
    ∀ Λ : atomic_lft, Λ ∈ κ → A !! Λ = Some true.
  Definition lft_dead_in (A : gmap atomic_lft bool) (κ : lft) : Prop :=
    ∃ Λ : atomic_lft, Λ ∈ κ ∧ A !! Λ = Some false.

  Definition lft_inv (A : gmap atomic_lft bool) (κ : lft) : iProp Σ :=
    (lft_inv_alive κ ∗ ⌜lft_alive_in A κ⌝ ∨
     lft_inv_dead κ ∗ ⌜lft_dead_in A κ⌝)%I.

  Definition lfts_inv : iProp Σ :=
    (∃ (A : gmap atomic_lft bool) (I : gmap lft lft_names),
      own_alft_auth A ∗
      own_ilft_auth I ∗
      [∗ set] κ ∈ dom _ I, lft_inv A κ)%I.

  Definition lft_ctx : iProp Σ := inv mgmtN lfts_inv.

  Definition lft_incl (κ κ' : lft) : iProp Σ :=
    (□ ((∀ q, lft_tok q κ ={↑lftN}=∗ ∃ q',
                 lft_tok q' κ' ∗ (lft_tok q' κ' ={↑lftN}=∗ lft_tok q κ)) ∗
        (lft_dead κ' ={↑lftN}=∗ lft_dead κ)))%I.

  Definition bor_idx := (lft * slice_name)%type.

  Definition idx_bor_own (q : frac) (i : bor_idx) : iProp Σ :=
    own_bor (i.1) (◯ {[ i.2 := (q,DecAgree Bor_in) ]}).
  Definition idx_bor (κ : lft) (i : bor_idx) (P : iProp Σ) : iProp Σ :=
    (lft_incl κ (i.1) ∗ slice borN (i.2) P)%I.
  Definition raw_bor (κ : lft) (P : iProp Σ) : iProp Σ :=
    (∃ s : slice_name, idx_bor_own 1 (κ, s) ∗ slice borN s P)%I.
  Definition bor (κ : lft) (P : iProp Σ) : iProp Σ :=
    (∃ κ', lft_incl κ κ' ∗ raw_bor κ' P)%I.
End defs.

Instance: Params (@lft_bor_alive) 4.
Instance: Params (@lft_inh) 5.
Instance: Params (@lft_vs) 4.
Instance: Params (@idx_bor) 5.
Instance: Params (@raw_bor) 4.
Instance: Params (@bor) 4.

Notation "q .[ κ ]" := (lft_tok q κ)
    (format "q .[ κ ]", at level 0) : uPred_scope.
Notation "[† κ ]" := (lft_dead κ) (format "[† κ ]"): uPred_scope.

Notation "&{ κ } P" := (bor κ P)
  (format "&{ κ }  P", at level 20, right associativity) : uPred_scope.
Notation "&{ κ , i } P" := (idx_bor κ i P)
  (format "&{ κ , i }  P", at level 20, right associativity) : uPred_scope.

Infix "⊑" := lft_incl (at level 70) : uPred_scope.

Typeclasses Opaque lft_tok lft_dead bor_cnt lft_bor_alive lft_bor_dead
  lft_inh lft_inv_alive lft_vs_inv lft_vs lft_inv_dead lft_inv lft_incl
  idx_bor_own idx_bor raw_bor bor.

Section basic_properties.
Context `{invG Σ, lftG Σ}.
Implicit Types κ : lft.

(* Unfolding lemmas *)
Lemma lft_vs_inv_go_ne κ (f f' : ∀ κ', κ' ⊂ κ → iProp Σ) I n :
  (∀ κ' (Hκ : κ' ⊂ κ), f κ' Hκ ≡{n}≡ f' κ' Hκ) →
  lft_vs_inv_go κ f I ≡{n}≡ lft_vs_inv_go κ f' I.
Proof.
  intros Hf. apply sep_ne, sep_ne, big_opS_ne=> // κ'.
  by apply forall_ne=> Hκ.
Qed.

Lemma lft_vs_go_ne κ (f f' : ∀ κ', κ' ⊂ κ → iProp Σ) Pb Pb' Pi Pi' n :
  (∀ κ' (Hκ : κ' ⊂ κ), f κ' Hκ ≡{n}≡ f' κ' Hκ) →
  Pb ≡{n}≡ Pb' → Pi ≡{n}≡ Pi' →
  lft_vs_go κ f Pb Pi ≡{n}≡ lft_vs_go κ f' Pb' Pi'.
Proof.
  intros Hf HPb HPi. apply exist_ne=> n'.
  apply sep_ne, forall_ne=> // I. rewrite lft_vs_inv_go_ne //. solve_proper.
Qed.

Lemma lft_inv_alive_go_ne κ (f f' : ∀ κ', κ' ⊂ κ → iProp Σ) n :
  (∀ κ' (Hκ : κ' ⊂ κ), f κ' Hκ ≡{n}≡ f' κ' Hκ) →
  lft_inv_alive_go κ f ≡{n}≡ lft_inv_alive_go κ f'.
Proof.
  intros Hf. apply exist_ne=> Pb; apply exist_ne=> Pi. by rewrite lft_vs_go_ne.
Qed.

Lemma lft_inv_alive_unfold κ :
  lft_inv_alive κ ⊣⊢ ∃ Pb Pi,
    lft_bor_alive κ Pb ∗ lft_vs κ Pb Pi ∗ lft_inh κ false Pi.
Proof.
  apply equiv_dist=> n. rewrite /lft_inv_alive -Fix_F_eq.
  apply lft_inv_alive_go_ne=> κ' Hκ.
  apply (Fix_F_proper _ (λ _, dist n)); auto using lft_inv_alive_go_ne.
Qed.
Lemma lft_vs_inv_unfold κ (I : gmap lft lft_names) :
  lft_vs_inv κ I ⊣⊢ lft_bor_dead κ ∗
    own_ilft_auth I ∗
    [∗ set] κ' ∈ dom _ I, ⌜κ' ⊂ κ⌝ → lft_inv_alive κ'.
Proof.
  rewrite /lft_vs_inv /lft_vs_inv_go. by setoid_rewrite pure_impl_forall.
Qed.
Lemma lft_vs_unfold κ Pb Pi :
  lft_vs κ Pb Pi ⊣⊢ ∃ n : nat,
    own_cnt κ (● n) ∗
    ∀ I : gmap lft lft_names,
      lft_vs_inv κ I -∗ ▷ Pb -∗ lft_dead κ ={⊤∖↑mgmtN}=∗
      lft_vs_inv κ I ∗ ▷ Pi ∗ own_cnt κ (◯ n).
Proof. done. Qed.

Global Instance lft_bor_alive_ne κ n : Proper (dist n ==> dist n) (lft_bor_alive κ).
Proof. solve_proper. Qed.
Global Instance lft_bor_alive_proper κ : Proper ((≡) ==> (≡)) (lft_bor_alive κ).
Proof. apply (ne_proper _). Qed.

Global Instance lft_inh_ne κ s n : Proper (dist n ==> dist n) (lft_inh κ s).
Proof. solve_proper. Qed.
Global Instance lft_inh_proper κ s : Proper ((≡) ==> (≡)) (lft_inh κ s).
Proof. apply (ne_proper _). Qed.

Global Instance lft_vs_ne κ n :
  Proper (dist n ==> dist n ==> dist n) (lft_vs κ).
Proof. intros P P' HP Q Q' HQ. by apply lft_vs_go_ne. Qed.
Global Instance lft_vs_proper κ : Proper ((≡) ==> (≡) ==> (≡)) (lft_vs κ).
Proof. apply (ne_proper_2 _). Qed.

Global Instance idx_bor_ne κ i n : Proper (dist n ==> dist n) (idx_bor κ i).
Proof. solve_proper. Qed.
Global Instance idx_bor_proper κ i : Proper ((≡) ==> (≡)) (idx_bor κ i).
Proof. apply (ne_proper _). Qed.

Global Instance raw_bor_ne i n : Proper (dist n ==> dist n) (raw_bor i).
Proof. solve_proper. Qed.
Global Instance raw_bor_proper i : Proper ((≡) ==> (≡)) (raw_bor i).
Proof. apply (ne_proper _). Qed.

Global Instance bor_ne κ n : Proper (dist n ==> dist n) (bor κ).
Proof. solve_proper. Qed.
Global Instance bor_proper κ : Proper ((≡) ==> (≡)) (bor κ).
Proof. apply (ne_proper _). Qed.

(*** PersistentP and TimelessP and instances  *)
Global Instance lft_tok_timeless q κ : TimelessP q.[κ].
Proof. rewrite /lft_tok. apply _. Qed.

Global Instance lft_dead_persistent κ : PersistentP [†κ].
Proof. rewrite /lft_dead. apply _. Qed.
Global Instance lft_dead_timeless κ : PersistentP [†κ].
Proof. rewrite /lft_tok. apply _. Qed.

Global Instance lft_incl_persistent κ κ' : PersistentP (κ ⊑ κ').
Proof. rewrite /lft_incl. apply _. Qed.

Global Instance idx_bor_persistent κ i P : PersistentP (&{κ,i} P).
Proof. rewrite /idx_bor. apply _. Qed.
Global Instance idx_bor_own_timeless q i : TimelessP (idx_bor_own q i).
Proof. rewrite /idx_bor_own. apply _. Qed.

Global Instance lft_ctx_persistent : PersistentP lft_ctx.
Proof. rewrite /lft_ctx. apply _. Qed.
End basic_properties.
