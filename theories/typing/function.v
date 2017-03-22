From iris.base_logic Require Import big_op.
From iris.proofmode Require Import tactics.
From iris.algebra Require Import vector.
From lrust.typing Require Export type.
From lrust.typing Require Import own programs cont.
Set Default Proof Using "Type".

Section fn.
  Context `{typeG Σ} {A : Type} {n : nat}.

  Record fn_params := FP' { fp_tys : vec type n; fp_ty : type; fp_E : lft → elctx }.

  Program Definition fn (fp : A → fn_params) : type :=
    {| st_own tid vl := (∃ fb kb xb e H,
         ⌜vl = [@RecV fb (kb::xb) e H]⌝ ∗ ⌜length xb = n⌝ ∗
         ▷ ∀ (x : A) (ϝ : lft) (k : val) (xl : vec val (length xb)),
            □ typed_body ((fp x).(fp_E)  ϝ) [ϝ ⊑ []]
                         [k◁cont([ϝ ⊑ []], λ v : vec _ 1, [v!!!0 ◁ box (fp x).(fp_ty)])]
                         (zip_with (TCtx_hasty ∘ of_val) xl
                                   (box <$> (vec_to_list (fp x).(fp_tys))))
                         (subst_v (fb::kb::xb) (RecV fb (kb::xb) e:::k:::xl) e))%I |}.
  Next Obligation.
    iIntros (fp tid vl) "H". iDestruct "H" as (fb kb xb e ?) "[% _]". by subst.
  Qed.

  Global Instance fn_send fp : Send (fn fp).
  Proof. iIntros (tid1 tid2 vl). done. Qed.

  Definition fn_params_rel (ty_rel : relation type) : relation fn_params :=
    λ fp1 fp2,
      Forall2 ty_rel fp2.(fp_tys) fp1.(fp_tys) ∧ ty_rel fp1.(fp_ty) fp2.(fp_ty) ∧
      pointwise_relation lft eq fp1.(fp_E) fp2.(fp_E).

  Global Instance fp_tys_proper R :
    Proper (flip (fn_params_rel R) ==> (Forall2 R : relation (vec _ _))) fp_tys.
  Proof. intros ?? HR. apply HR. Qed.
  Global Instance fp_tys_proper_flip R :
    Proper (fn_params_rel R ==> flip (Forall2 R : relation (vec _ _))) fp_tys.
  Proof. intros ?? HR. apply HR. Qed.

  Global Instance fp_ty_proper R :
    Proper (fn_params_rel R ==> R) fp_ty.
  Proof. intros ?? HR. apply HR. Qed.

  Global Instance fp_E_proper R :
    Proper (fn_params_rel R ==> eq ==> eq) fp_E.
  Proof. intros ?? HR ??->. apply HR. Qed.

  Global Instance FP_proper R :
    Proper (flip (Forall2 R : relation (vec _ _)) ==> R ==>
            pointwise_relation lft eq ==> fn_params_rel R) FP'.
  Proof. by split; [|split]. Qed.

  Global Instance fn_type_contractive n' :
    Proper (pointwise_relation A (fn_params_rel (type_dist2_later n')) ==>
            type_dist2 n') fn.
  Proof.
    intros fp1 fp2 Hfp. apply ty_of_st_type_ne. destruct n'; first done.
    constructor; unfold ty_own; simpl.
    (* TODO: 'f_equiv' is slow here because reflexivity is slow. *)
    (* The clean way to do this would be to have a metric on type contexts. Oh well. *)
    intros tid vl. unfold typed_body.
    do 12 f_equiv. f_contractive. do 16 ((eapply fp_E_proper; try reflexivity) || exact: Hfp || f_equiv).
    - rewrite !cctx_interp_singleton /=. do 5 f_equiv.
      rewrite !tctx_interp_singleton /tctx_elt_interp /=. repeat (apply Hfp || f_equiv).
    - rewrite /tctx_interp !big_sepL_zip_with /=. do 4 f_equiv.
      cut (∀ n tid p i, Proper (dist n ==> dist n)
        (λ (l : list _), ∀ ty, ⌜l !! i = Some ty⌝ → tctx_elt_interp tid (p ◁ ty))%I).
      { intros Hprop. apply Hprop, list_fmap_ne; last first.
        - symmetry. eapply Forall2_impl; first apply Hfp. intros.
          apply dist_later_dist, type_dist2_dist_later. done.
        - apply _. }
      clear. intros n tid p i x y. rewrite list_dist_lookup=>Hxy.
      specialize (Hxy i). destruct (x !! i) as [tyx|], (y !! i) as [tyy|];
        inversion_clear Hxy; last done.
      transitivity (tctx_elt_interp tid (p ◁ tyx));
        last transitivity (tctx_elt_interp tid (p ◁ tyy)); last 2 first.
      + unfold tctx_elt_interp. do 3 f_equiv. by apply ty_own_ne.
      + apply equiv_dist. iSplit.
        * iIntros "H * #EQ". by iDestruct "EQ" as %[=->].
        * iIntros "H". by iApply "H".
      + apply equiv_dist. iSplit.
        * iIntros "H". by iApply "H".
        * iIntros "H * #EQ". by iDestruct "EQ" as %[=->].
  Qed.

  Global Instance fn_ne n' :
    Proper (pointwise_relation A (fn_params_rel (dist n')) ==> dist n') fn.
  Proof.
    intros ?? Hfp. apply dist_later_dist, type_dist2_dist_later.
    apply fn_type_contractive=>u. split; last split.
    - eapply Forall2_impl; first apply Hfp. intros. simpl.
      apply type_dist_dist2. done.
    - apply type_dist_dist2. apply Hfp.
    - apply Hfp.
  Qed.
End fn.

Arguments fn_params {_ _} _.

(* The parameter of [FP'] are in the wrong order in order to make sure
   that type-checking is done in that order, so that the [ELCtx_Alive]
   is taken as a coercion. We reestablish the intuitive order with
   [FP] *)
Notation FP E tys ty := (FP' tys ty E).

(* We use recursive notation for binders as well, to allow patterns
   like '(a, b) to be used. In practice, only one binder is ever used,
   but using recursive binders is the only way to make Coq accept
   patterns. *)
(* FIXME : because of a bug in Coq, such patterns only work for
   printing. Once on 8.6pl1, this should work.  *)
Notation "'fn(∀' x .. x' ',' E ';' T1 ',' .. ',' TN ')' '→' R" :=
  (fn (λ x, (.. (λ x',
      FP E%EL (Vector.cons T1 .. (Vector.cons TN Vector.nil) ..)%T R%T)..)))
  (at level 99, R at level 200, x binder, x' binder,
   format "'fn(∀'  x .. x' ','  E ';'  T1 ','  .. ','  TN ')'  '→'  R") : lrust_type_scope.
Notation "'fn(∀' x .. x' ',' E ')' '→' R" :=
  (fn (λ x, (.. (λ x', FP E%EL Vector.nil R%T)..)))
  (at level 99, R at level 200, x binder, x' binder,
   format "'fn(∀'  x .. x' ','  E ')'  '→'  R") : lrust_type_scope.
Notation "'fn(' E ';' T1 ',' .. ',' TN ')' '→' R" :=
  (fn (λ _:(), FP E%EL (Vector.cons T1 .. (Vector.cons TN Vector.nil) ..) R%T))
  (at level 99, R at level 200,
   format "'fn(' E ';'  T1 ','  .. ','  TN ')'  '→'  R") : lrust_type_scope.
Notation "'fn(' E ')' '→' R" :=
  (fn (λ _:(), FP E%EL Vector.nil R%T))
  (at level 99, R at level 200,
   format "'fn(' E ')'  '→'  R") : lrust_type_scope.

Section typing.
  Context `{typeG Σ}.

  Lemma fn_subtype {A n} E0 L0 (fp fp' : A → fn_params n) :
    (∀ x ϝ, let EE := E0 ++ (fp' x).(fp_E) ϝ in
            elctx_sat EE L0 ((fp x).(fp_E) ϝ) ∧
            Forall2 (subtype EE L0) (fp' x).(fp_tys) (fp x).(fp_tys) ∧
            subtype EE L0 (fp x).(fp_ty) (fp' x).(fp_ty)) →
    subtype E0 L0 (fn fp) (fn fp').
  Proof.
    intros Hcons. apply subtype_simple_type=>//= qL. iIntros "HL0".
    (* We massage things so that we can throw away HL0 before going under the box. *)
    iAssert (∀ x ϝ, let EE := E0 ++ (fp' x).(fp_E) ϝ in □ (elctx_interp EE -∗
                 elctx_interp ((fp x).(fp_E) ϝ) ∗
                 ([∗ list] tys ∈ (zip (fp' x).(fp_tys) (fp x).(fp_tys)), type_incl (tys.1) (tys.2)) ∗
                 type_incl (fp x).(fp_ty) (fp' x).(fp_ty)))%I as "#Hcons".
    { iIntros (x ϝ). destruct (Hcons x ϝ) as (HE &Htys &Hty). clear Hcons.
      iDestruct (HE with "HL0") as "#HE".
      iDestruct (subtype_Forall2_llctx with "HL0") as "#Htys"; first done.
      iDestruct (Hty with "HL0") as "#Hty".
      iClear "∗". iIntros "!# #HEE".
      iSplit; last iSplit.
      - by iApply "HE".
      - by iApply "Htys".
      - by iApply "Hty". }
    iClear "∗". clear Hcons. iIntros "!# #HE0 * Hf".
    iDestruct "Hf" as (fb kb xb e ?) "[% [% #Hf]]". subst.
    iExists fb, kb, xb, e, _. iSplit. done. iSplit. done. iNext.
    rewrite /typed_body. iIntros (x ϝ k xl) "!# * #LFT #HE' Htl HL HC HT".
    iDestruct ("Hcons" with "[$]") as "#(HE & Htys & Hty)".
    iApply ("Hf" with "LFT HE Htl HL [HC] [HT]").
    - unfold cctx_interp. iIntros (elt) "Helt".
      iDestruct "Helt" as %->%elem_of_list_singleton. iIntros (ret) "Htl HL HT".
      unfold cctx_elt_interp.
      iApply ("HC" $! (_ ◁cont(_, _)%CC) with "[%] Htl HL [> -]").
      { by apply elem_of_list_singleton. }
      rewrite /tctx_interp !big_sepL_singleton /=.
      iDestruct "HT" as (v) "[HP Hown]". iExists v. iFrame "HP".
      iDestruct (box_type_incl with "[$Hty]") as "(_ & #Hincl & _)".
      by iApply "Hincl".
    - iClear "Hf". rewrite /tctx_interp
         -{2}(fst_zip (fp x).(fp_tys) (fp' x).(fp_tys)) ?vec_to_list_length //
         -{2}(snd_zip (fp x).(fp_tys) (fp' x).(fp_tys)) ?vec_to_list_length //
         !zip_with_fmap_r !(zip_with_zip (λ _ _, (_ ∘ _) _ _)) !big_sepL_fmap.
      iApply big_sepL_impl. iSplit; last done. iIntros "{HT Hty}!#".
      iIntros (i [p [ty1' ty2']]) "#Hzip H /=".
      iDestruct "H" as (v) "[? Hown]". iExists v. iFrame.
      rewrite !lookup_zip_with.
      iDestruct "Hzip" as %(? & ? & ([? ?] & (? & Hty'1 &
        (? & Hty'2 & [=->->])%bind_Some)%bind_Some & [=->->->])%bind_Some)%bind_Some.
      iDestruct (big_sepL_lookup with "Htys") as "#Hty".
      { rewrite lookup_zip_with /=. erewrite Hty'2. simpl. by erewrite Hty'1. }
      iDestruct (box_type_incl with "[$Hty]") as "(_ & #Hincl & _)".
      by iApply "Hincl".
  Qed.

  (* This proper and the next can probably not be inferred, but oh well. *)
  Global Instance fn_subtype' {A n} E0 L0 :
    Proper (pointwise_relation A (fn_params_rel (n:=n) (subtype E0 L0)) ==>
            subtype E0 L0) fn.
  Proof.
    intros fp1 fp2 Hfp. apply fn_subtype=>x ϝ. destruct (Hfp x) as (Htys & Hty & HE).
    split; last split.
    - rewrite (HE ϝ). apply elctx_sat_app_weaken_l, elctx_sat_refl.
    - eapply Forall2_impl; first eapply Htys. intros ??.
      eapply subtype_weaken; last done. by apply submseteq_inserts_r.
    - eapply subtype_weaken, Hty; last done. by apply submseteq_inserts_r.
  Qed.

  Global Instance fn_eqtype' {A n} E0 L0 :
    Proper (pointwise_relation A (fn_params_rel (n:=n) (eqtype E0 L0)) ==>
            eqtype E0 L0) fn.
  Proof.
    intros fp1 fp2 Hfp. split; eapply fn_subtype=>x ϝ; destruct (Hfp x) as (Htys & Hty & HE); (split; last split).
    - rewrite (HE ϝ). apply elctx_sat_app_weaken_l, elctx_sat_refl.
    - eapply Forall2_impl; first eapply Htys. intros t1 t2 Ht.
      eapply subtype_weaken; last apply Ht; last done. by apply submseteq_inserts_r.
    - eapply subtype_weaken; last apply Hty; last done. by apply submseteq_inserts_r.
    - rewrite (HE ϝ). apply elctx_sat_app_weaken_l, elctx_sat_refl.
    - symmetry in Htys. eapply Forall2_impl; first eapply Htys. intros t1 t2 Ht.
      eapply subtype_weaken; last apply Ht; last done. by apply submseteq_inserts_r.
    - eapply subtype_weaken; last apply Hty; last done. by apply submseteq_inserts_r.
  Qed.

  Lemma fn_subtype_specialize {A B n} (σ : A → B) E0 L0 fp :
    subtype E0 L0 (fn (n:=n) fp) (fn (fp ∘ σ)).
  Proof.
    apply subtype_simple_type=>//= qL.
    iIntros "_ !# _ * Hf". iDestruct "Hf" as (fb kb xb e ?) "[% [% #Hf]]". subst.
    iExists fb, kb, xb, e, _. iSplit. done. iSplit. done.
    rewrite /typed_body. iNext. iIntros "*". iApply "Hf".
  Qed.

  Lemma type_call' {A} E L T p (κs : list lft) (ps : list path)
                         (fp : A → fn_params (length ps)) (k : val) x :
    Forall (lctx_lft_alive E L) κs →
    (∀ ϝ, elctx_sat (((λ κ, ϝ ⊑ κ) <$> κs)%EL ++ E) L ((fp x).(fp_E) ϝ)) →
    typed_body E L [k ◁cont(L, λ v : vec _ 1, (v!!!0 ◁ box (fp x).(fp_ty)) :: T)]
               ((p ◁ fn fp) ::
                zip_with TCtx_hasty ps (box <$> (vec_to_list (fp x).(fp_tys))) ++
                T)
               (call: p ps → k).
  Proof.
    iIntros (Hκs HE tid) "#LFT #HE Htl HL HC (Hf & Hargs & HT)".
    wp_apply (wp_hasty with "Hf"). iIntros (v) "% Hf".
    iApply (wp_app_vec _ _ (_::_) ((λ v, ⌜v = (λ: ["_r"], (#() ;; #()) ;; k ["_r"])%V⌝):::
               vmap (λ ty (v : val), tctx_elt_interp tid (v ◁ box ty)) (fp x).(fp_tys))%I
            with "[Hargs]"); first wp_done.
    - rewrite /= big_sepL_cons. iSplitR "Hargs".
      { simpl. iApply wp_value; last done. solve_to_val. }
      clear dependent k p.
      rewrite /tctx_interp vec_to_list_map !zip_with_fmap_r
              (zip_with_zip (λ e ty, (e, _))) zip_with_zip !big_sepL_fmap.
      iApply (big_sepL_mono' with "Hargs"). iIntros (i [p ty]) "HT/=".
      iApply (wp_hasty with "HT"). setoid_rewrite tctx_hasty_val. iIntros (?) "? $".
    - simpl. change (@length expr ps) with (length ps).
      iIntros (vl'). inv_vec vl'=>kv vl. rewrite /= big_sepL_cons.
      iIntros "/= [% Hvl]". subst kv. iDestruct "Hf" as (fb kb xb e ?) "[EQ [EQl #Hf]]".
      iDestruct "EQ" as %[=->]. iDestruct "EQl" as %EQl. revert vl fp HE.
      rewrite <-EQl=>vl fp HE. iApply wp_rec; try done.
      { rewrite -fmap_cons Forall_fmap Forall_forall=>? _. rewrite /= to_of_val. eauto. }
      { rewrite -fmap_cons -(subst_v_eq (fb::kb::xb) (_:::_:::vl)) //. }
      iNext. iMod (lft_create with "LFT") as (ϝ) "[Htk #Hinh]"; first done.
      iSpecialize ("Hf" $! x ϝ _ vl).
      iDestruct (HE ϝ with "HL") as "#HE'".
      iMod (lctx_lft_alive_list with "LFT [# $HE //] HL") as "[#HEE Hclose]"; [done..|].
      iApply ("Hf" with "LFT [>] Htl [Htk] [HC HT Hclose]").
      + iApply "HE'". iFrame "#". auto.
      + iSplitL; last done. iExists ϝ. iSplit; first by rewrite /= left_id.
        iFrame "#∗".
      + iIntros (y) "IN". iDestruct "IN" as %->%elem_of_list_singleton.
        iIntros (args) "Htl [HL _] Hret". inv_vec args=>r.
        iDestruct "HL" as  (κ') "(EQ & Htk & _)". iDestruct "EQ" as %EQ.
        rewrite /= left_id in EQ. subst κ'. simpl. wp_rec. wp_bind Endlft.
        iSpecialize ("Hinh" with "Htk").
        iApply (wp_mask_mono (↑lftN)); first done.
        iApply (wp_step_fupd with "Hinh"); [set_solver+..|]. wp_seq.
        iIntros "#Htok !>". wp_seq. iMod ("Hclose" with "Htok") as "HL".
        iSpecialize ("HC" with "[]"); first by (iPureIntro; apply elem_of_list_singleton).
        iApply ("HC" $! [#r] with "Htl HL").
        rewrite tctx_interp_singleton tctx_interp_cons. iFrame.
      + rewrite /tctx_interp vec_to_list_map !zip_with_fmap_r
                (zip_with_zip (λ v ty, (v, _))) zip_with_zip !big_sepL_fmap.
        iApply (big_sepL_mono' with "Hvl"). by iIntros (i [v ty']).
  Qed.

  Lemma type_call {A} x E L C T T' T'' p (ps : list path)
                        (fp : A → fn_params (length ps)) k :
    (p ◁ fn fp)%TC ∈ T →
    Forall (lctx_lft_alive E L) (L.*1) →
    (∀ ϝ, elctx_sat (((λ κ, ϝ ⊑ κ) <$> (L.*1))%EL ++ E) L ((fp x).(fp_E) ϝ)) →
    tctx_extract_ctx E L (zip_with TCtx_hasty ps
                                   (box <$> vec_to_list (fp x).(fp_tys))) T T' →
    (k ◁cont(L, T''))%CC ∈ C →
    (∀ ret : val, tctx_incl E L ((ret ◁ box (fp x).(fp_ty))::T') (T'' [# ret])) →
    typed_body E L C T (call: p ps → k).
  Proof.
    intros Hfn HL HE HTT' HC HT'T''.
    rewrite -typed_body_mono /flip; last done; first by eapply type_call'.
    - etrans. eapply (incl_cctx_incl _ [_]); first by intros ? ->%elem_of_list_singleton.
      apply cctx_incl_cons_match; first done. intros args. by inv_vec args.
    - etrans; last by apply (tctx_incl_frame_l [_]).
      apply copy_elem_of_tctx_incl; last done. apply _.
  Qed.

  Lemma type_letcall {A} x E L C T T' p (ps : list path)
                        (fp : A → fn_params (length ps)) b e :
    Closed (b :b: []) e → Closed [] p → Forall (Closed []) ps →
    (p ◁ fn fp)%TC ∈ T →
    Forall (lctx_lft_alive E L) (L.*1) →
    (∀ ϝ, elctx_sat (((λ κ, ϝ ⊑ κ) <$> (L.*1))%EL ++ E) L ((fp x).(fp_E) ϝ)) →
    tctx_extract_ctx E L (zip_with TCtx_hasty ps
                                   (box <$> vec_to_list (fp x).(fp_tys))) T T' →
    (∀ ret : val, typed_body E L C ((ret ◁ box (fp x).(fp_ty))::T') (subst' b ret e)) -∗
    typed_body E L C T (letcall: b := p ps in e).
  Proof.
    iIntros (?? Hpsc ????) "He".
    iApply (type_cont_norec [_] _ (λ r, (r!!!0 ◁ box (fp x).(fp_ty)) :: T')%TC).
    - (* TODO : make [solve_closed] work here. *)
      eapply is_closed_weaken; first done. set_solver+.
    - (* TODO : make [solve_closed] work here. *)
      rewrite /Closed /= !andb_True. split.
      + by eapply is_closed_weaken, list_subseteq_nil.
      + eapply Is_true_eq_left, forallb_forall, List.Forall_forall, Forall_impl=>//.
        intros. eapply Is_true_eq_true, is_closed_weaken=>//. set_solver+.
    - iIntros (k).
      (* TODO : make [simpl_subst] work here. *)
      change (subst' "_k" k (p ((λ: ["_r"], (#() ;; #()) ;; "_k" ["_r"])%E :: ps))) with
             ((subst "_k" k p) ((λ: ["_r"], (#() ;; #()) ;; k ["_r"])%E :: map (subst "_k" k) ps)).
      rewrite is_closed_nil_subst //.
      assert (map (subst "_k" k) ps = ps) as ->.
      { clear -Hpsc. induction Hpsc=>//=. rewrite is_closed_nil_subst //. congruence. }
      iApply type_call; try done. constructor. done.
    - simpl. iIntros (k ret). inv_vec ret=>ret. rewrite /subst_v /=.
      rewrite ->(is_closed_subst []); last set_solver+; last first.
      { apply subst'_is_closed; last done. apply is_closed_of_val. }
      (iApply typed_body_mono; last by iApply "He"); [|done..].
      apply incl_cctx_incl. set_solver+.
  Qed.

  Lemma type_rec {A} E L fb (argsb : list binder) ef e n
        (fp : A → fn_params n) T `{!CopyC T, !SendC T} :
    ef = (funrec: fb argsb := e)%E →
    n = length argsb →
    Closed (fb :b: "return" :b: argsb +b+ []) e →
    □ (∀ x ϝ (f : val) k (args : vec val (length argsb)),
          typed_body ((fp x).(fp_E) ϝ) [ϝ ⊑ []]
                     [k ◁cont([ϝ ⊑ []], λ v : vec _ 1, [v!!!0 ◁ box (fp x).(fp_ty)])]
                     ((f ◁ fn fp) ::
                        zip_with (TCtx_hasty ∘ of_val) args
                                 (box <$> vec_to_list (fp x).(fp_tys)) ++ T)
                     (subst_v (fb :: BNamed "return" :: argsb) (f ::: k ::: args) e)) -∗
    typed_instruction_ty E L T ef (fn fp).
  Proof.
    iIntros (-> -> Hc) "#Hbody". iIntros (tid) "#LFT _ $ $ #HT". iApply wp_value.
    { simpl. rewrite ->(decide_left Hc). done. }
    rewrite tctx_interp_singleton. iLöb as "IH". iExists _. iSplit.
    { simpl. rewrite decide_left. done. }
    iExists fb, _, argsb, e, _. iSplit. done. iSplit. done. iNext.
    iIntros (x ϝ k args) "!#". iIntros (tid') "_ HE Htl HL HC HT'".
    iApply ("Hbody" with "LFT HE Htl HL HC").
    rewrite tctx_interp_cons tctx_interp_app. iFrame "HT' IH".
    by iApply sendc_change_tid.
  Qed.

  Lemma type_fn {A} E L (argsb : list binder) ef e n
        (fp : A → fn_params n) T `{!CopyC T, !SendC T} :
    ef = (funrec: <> argsb := e)%E →
    n = length argsb →
    Closed ("return" :b: argsb +b+ []) e →
    □ (∀ x ϝ k (args : vec val (length argsb)),
        typed_body ((fp x).(fp_E) ϝ) [ϝ ⊑ []]
                   [k ◁cont([ϝ ⊑ []], λ v : vec _ 1, [v!!!0 ◁ box (fp x).(fp_ty)])]
                   (zip_with (TCtx_hasty ∘ of_val) args
                             (box <$> vec_to_list (fp x).(fp_tys)) ++ T)
                   (subst_v (BNamed "return" :: argsb) (k ::: args) e)) -∗
    typed_instruction_ty E L T ef (fn fp).
  Proof.
    iIntros (???) "#He". iApply type_rec; try done. iIntros "!# *".
    iApply typed_body_mono; last iApply "He"; try done.
    eapply contains_tctx_incl. by constructor.
  Qed.
End typing.

Hint Resolve fn_subtype : lrust_typing.
