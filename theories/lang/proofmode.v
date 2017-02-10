From iris.base_logic Require Import namespaces.
From iris.program_logic Require Export weakestpre.
From iris.proofmode Require Import coq_tactics.
From iris.proofmode Require Export tactics.
From lrust.lang Require Export tactics derived heap.
Set Default Proof Using "Type".
Import uPred.

(** wp-specific helper tactics *)
Ltac wp_bind_core K :=
  lazymatch eval hnf in K with
  | [] => idtac
  | _ => etrans; [|fast_by apply (wp_bind K)]; simpl
  end.

(* Solves side-conditions generated by the wp tactics *)
Ltac wp_done :=
  match goal with
  | |- Closed _ _ => solve_closed
  | |- is_Some (to_val _) => solve_to_val
  | |- to_val _ = Some _ => solve_to_val
  | |- language.to_val _ = Some _ => solve_to_val
  | |- Forall _ [] => fast_by apply List.Forall_nil
  | |- Forall _ (_ :: _) => apply List.Forall_cons; wp_done
  | _ => fast_done
  end.

Ltac wp_value_head := etrans; [|eapply wp_value; wp_done]; lazy beta.

Ltac wp_seq_head :=
  lazymatch goal with
  | |- _ ⊢ wp ?E (Seq _ _) ?Q =>
    etrans; [|eapply wp_seq; wp_done]; iNext
  end.

Ltac wp_finish := intros_revert ltac:(
  rewrite /= ?to_of_val;
  try iNext;
  repeat lazymatch goal with
  | |- _ ⊢ wp ?E (Seq _ _) ?Q =>
     etrans; [|eapply wp_seq; wp_done]; iNext
  | |- _ ⊢ wp ?E _ ?Q => wp_value_head
  end).

Tactic Notation "wp_value" :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q => reshape_expr e ltac:(fun K e' =>
    wp_bind_core K; wp_value_head) || fail "wp_value: cannot find value in" e
  | _ => fail "wp_value: not a wp"
  end.

Lemma of_val_unlock v e : of_val v = e → of_val (locked v) = e.
Proof. by unlock. Qed.

(* Applied to goals that are equalities of expressions. Will try to unlock the
   LHS once if necessary, to get rid of the lock added by the syntactic sugar. *)
Ltac solve_of_val_unlock := try apply of_val_unlock; reflexivity.

Tactic Notation "wp_rec" :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q => reshape_expr e ltac:(fun K e' =>
    match eval hnf in e' with App ?e1 _ =>
(* hnf does not reduce through an of_val *)
(*      match eval hnf in e1 with Rec _ _ _ => *)
    wp_bind_core K; etrans;
      [|eapply wp_rec; [solve_of_val_unlock|wp_done..]]; simpl_subst; wp_finish
(*      end *) end) || fail "wp_rec: cannot find 'Rec' in" e
  | _ => fail "wp_rec: not a 'wp'"
  end.

Tactic Notation "wp_lam" :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q => reshape_expr e ltac:(fun K e' =>
    match eval hnf in e' with App ?e1 _ =>
(*    match eval hnf in e1 with Rec BAnon _ _ => *)
    wp_bind_core K; etrans;
      [|eapply wp_lam; [solve_of_val_unlock|wp_done..]]; simpl_subst; wp_finish
(*    end *) end) || fail "wp_lam: cannot find 'Lam' in" e
  | _ => fail "wp_lam: not a 'wp'"
  end.

Tactic Notation "wp_let" := wp_lam.
Tactic Notation "wp_seq" := wp_let.

Tactic Notation "wp_op" :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q => reshape_expr e ltac:(fun K e' =>
    match eval hnf in e' with
    | BinOp LeOp _ _ => wp_bind_core K; apply wp_le; wp_finish
    | BinOp EqOp _ _ => wp_bind_core K; apply wp_eq_int; wp_finish
    | BinOp OffsetOp _ _ =>
       wp_bind_core K; etrans; [|eapply wp_offset; try fast_done]; wp_finish
    | BinOp PlusOp _ _ =>
       wp_bind_core K; etrans; [|eapply wp_plus; try fast_done]; wp_finish
    | BinOp MinusOp _ _ =>
       wp_bind_core K; etrans; [|eapply wp_minus; try fast_done]; wp_finish
    end) || fail "wp_op: cannot find 'BinOp' in" e
  | _ => fail "wp_op: not a 'wp'"
  end.

Tactic Notation "wp_if" :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q => reshape_expr e ltac:(fun K e' =>
    match eval hnf in e' with
    | If _ _ _ =>
      wp_bind_core K;
      etrans; [|eapply wp_if]; wp_finish
    end) || fail "wp_if: cannot find 'If' in" e
  | _ => fail "wp_if: not a 'wp'"
  end.

Tactic Notation "wp_case" :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q => reshape_expr e ltac:(fun K e' =>
    match eval hnf in e' with
    | Case _ _ _ =>
      wp_bind_core K;
      etrans; [|eapply wp_case; wp_done];
      simpl_subst; wp_finish
    end) || fail "wp_case: cannot find 'Case' in" e
  | _ => fail "wp_case: not a 'wp'"
  end.

Tactic Notation "wp_bind" open_constr(efoc) :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q => reshape_expr e ltac:(fun K e' =>
    match e' with
    | efoc => unify e' efoc; wp_bind_core K
    end) || fail "wp_bind: cannot find" efoc "in" e
  | _ => fail "wp_bind: not a 'wp'"
  end.

Section heap.
Context `{lrustG Σ}.
Implicit Types P Q : iProp Σ.
Implicit Types Φ : val → iProp Σ.
Implicit Types Δ : envs (iResUR Σ).

Lemma tac_wp_alloc Δ Δ' E j1 j2 n Φ :
  0 < n →
  IntoLaterNEnvs 1 Δ Δ' →
  (∀ l sz (vl : vec val sz), n = sz → ∃ Δ'',
    envs_app false (Esnoc (Esnoc Enil j1 (l ↦∗ vl)) j2 (†l…(Z.to_nat n))) Δ'
      = Some Δ'' ∧
    (Δ'' ⊢ Φ (LitV $ LitLoc l))) →
  Δ ⊢ WP Alloc (Lit $ LitInt n) @ E {{ Φ }}.
Proof.
  intros ?? HΔ. rewrite -wp_fupd. eapply wand_apply; first exact:wp_alloc.
  rewrite -always_and_sep_l. apply and_intro; first done.
  rewrite into_laterN_env_sound; apply later_mono, forall_intro=> l.
  apply forall_intro=>sz. apply forall_intro=> vl. apply wand_intro_l. rewrite -assoc.
  apply pure_elim_sep_l=> Hn. apply wand_elim_r'.
  destruct (HΔ l _ vl) as (Δ''&?&HΔ'); first done.
  rewrite envs_app_sound //; simpl. by rewrite right_id HΔ' -fupd_intro.
Qed.

Lemma tac_wp_free Δ Δ' Δ'' Δ''' E i1 i2 vl (n : Z) (n' : nat) l Φ :
  n = length vl →
  IntoLaterNEnvs 1 Δ Δ' →
  envs_lookup i1 Δ' = Some (false, l ↦∗ vl)%I →
  envs_delete i1 false Δ' = Δ'' →
  envs_lookup i2 Δ'' = Some (false, †l…n')%I →
  envs_delete i2 false Δ'' = Δ''' →
  n' = length vl →
  (Δ''' ⊢ Φ (LitV LitUnit)) →
  Δ ⊢ WP Free (Lit $ LitInt n) (Lit $ LitLoc l) @ E {{ Φ }}.
Proof.
  intros -> ?? <- ? <- -> HΔ. rewrite -wp_fupd.
  eapply wand_apply; first exact:wp_free; simpl.
  rewrite into_laterN_env_sound -!later_sep; apply later_mono.
  do 2 (rewrite envs_lookup_sound' //).
  by rewrite HΔ wand_True -fupd_intro -assoc.
Qed.

Lemma tac_wp_read Δ Δ' E i l q v o Φ :
  o = Na1Ord ∨ o = ScOrd →
  IntoLaterNEnvs 1 Δ Δ' →
  envs_lookup i Δ' = Some (false, l ↦{q} v)%I →
  (Δ' ⊢ Φ v) →
  Δ ⊢ WP Read o (Lit $ LitLoc l) @ E {{ Φ }}.
Proof.
  intros [->| ->] ???.
  - rewrite -wp_fupd. eapply wand_apply; first exact:wp_read_na.
    rewrite into_laterN_env_sound -later_sep envs_lookup_split //; simpl.
      rewrite -fupd_intro. by apply later_mono, sep_mono_r, wand_mono.
  - rewrite -wp_fupd. eapply wand_apply; first exact:wp_read_sc.
    rewrite into_laterN_env_sound -later_sep envs_lookup_split //; simpl.
      rewrite -fupd_intro. by apply later_mono, sep_mono_r, wand_mono.
Qed.

Lemma tac_wp_write Δ Δ' Δ'' E i l v e v' o Φ :
  to_val e = Some v' →
  o = Na1Ord ∨ o = ScOrd →
  IntoLaterNEnvs 1 Δ Δ' →
  envs_lookup i Δ' = Some (false, l ↦ v)%I →
  envs_simple_replace i false (Esnoc Enil i (l ↦ v')) Δ' = Some Δ'' →
  (Δ'' ⊢ Φ (LitV LitUnit)) →
  Δ ⊢ WP Write o (Lit $ LitLoc l) e @ E {{ Φ }}.
Proof.
  intros ? [->| ->] ????.
  - rewrite -wp_fupd. eapply wand_apply; first by apply wp_write_na.
    rewrite into_laterN_env_sound -later_sep envs_simple_replace_sound //; simpl.
    rewrite right_id -fupd_intro. by apply later_mono, sep_mono_r, wand_mono.
  - rewrite -wp_fupd. eapply wand_apply; first by apply wp_write_sc.
    rewrite into_laterN_env_sound -later_sep envs_simple_replace_sound //; simpl.
    rewrite right_id -fupd_intro. by apply later_mono, sep_mono_r, wand_mono.
Qed.
End heap.

Tactic Notation "wp_apply" open_constr(lem) :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q => reshape_expr e ltac:(fun K e' =>
    wp_bind_core K; iApply lem; try iNext; simpl)
  | _ => fail "wp_apply: not a 'wp'"
  end.

Tactic Notation "wp_alloc" ident(l) ident(vl) "as" constr(H) constr(Hf) :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q =>
    first
      [reshape_expr e ltac:(fun K e' =>
         match eval hnf in e' with Alloc _ => wp_bind_core K end)
      |fail 1 "wp_alloc: cannot find 'Alloc' in" e];
    eapply tac_wp_alloc with _ H Hf;
      [try fast_done
      |apply _
      |let sz := fresh "sz" in let Hsz := fresh "Hsz" in
       first [intros l sz vl Hsz | fail 1 "wp_alloc:" l "or" vl "not fresh"];
       (* If Hsz is "constant Z = nat", change that to an equation on nat and
          potentially substitute away the sz. *)
       try (match goal with Hsz : ?x = _ |- _ => rewrite <-(Z2Nat.id x) in Hsz; last done end;
            apply Nat2Z.inj in Hsz;
            try (cbv [Z.to_nat Pos.to_nat] in Hsz;
                 simpl in Hsz;
                 (* Substitute only if we have a literal nat. *)
                 match goal with Hsz : S _ = _ |- _ => subst sz end));
        eexists; split;
          [env_cbv; reflexivity || fail "wp_alloc:" H "or" Hf "not fresh"
          |wp_finish]]
  | _ => fail "wp_alloc: not a 'wp'"
  end.

Tactic Notation "wp_alloc" ident(l) ident(vl) :=
  let H := iFresh in let Hf := iFresh in wp_alloc l vl as H Hf.

Tactic Notation "wp_free" :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q =>
    first
      [reshape_expr e ltac:(fun K e' =>
         match eval hnf in e' with Free _ _ => wp_bind_core K end)
      |fail 1 "wp_free: cannot find 'Free' in" e];
    eapply tac_wp_free;
      [try fast_done
      |apply _
      |let l := match goal with |- _ = Some (_, (?l ↦∗ _)%I) => l end in
       iAssumptionCore || fail "wp_free: cannot find" l "↦∗ ?"
      |env_cbv; reflexivity
      |let l := match goal with |- _ = Some (_, († ?l … _)%I) => l end in
       iAssumptionCore || fail "wp_free: cannot find †" l "… ?"
      |env_cbv; reflexivity
      |try fast_done
      |wp_finish]
  | _ => fail "wp_free: not a 'wp'"
  end.

Tactic Notation "wp_read" :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q =>
    first
      [reshape_expr e ltac:(fun K e' =>
         match eval hnf in e' with Read _ _ => wp_bind_core K end)
      |fail 1 "wp_read: cannot find 'Read' in" e];
    eapply tac_wp_read;
      [(right; fast_done) || (left; fast_done) ||
       fail "wp_read: order is neither Na2Ord nor ScOrd"
      |apply _
      |let l := match goal with |- _ = Some (_, (?l ↦{_} _)%I) => l end in
       iAssumptionCore || fail "wp_read: cannot find" l "↦ ?"
      |wp_finish]
  | _ => fail "wp_read: not a 'wp'"
  end.

Tactic Notation "wp_write" :=
  iStartProof;
  lazymatch goal with
  | |- _ ⊢ wp ?E ?e ?Q =>
    first
      [reshape_expr e ltac:(fun K e' =>
         match eval hnf in e' with Write _ _ _ => wp_bind_core K end)
      |fail 1 "wp_write: cannot find 'Write' in" e];
    eapply tac_wp_write;
      [let e' := match goal with |- to_val ?e' = _ => e' end in
       wp_done || fail "wp_write:" e' "not a value"
      |(right; fast_done) || (left; fast_done) ||
       fail "wp_write: order is neither Na2Ord nor ScOrd"
      |apply _
      |let l := match goal with |- _ = Some (_, (?l ↦{_} _)%I) => l end in
       iAssumptionCore || fail "wp_write: cannot find" l "↦ ?"
      |env_cbv; reflexivity
      |wp_finish]
  | _ => fail "wp_write: not a 'wp'"
  end.
