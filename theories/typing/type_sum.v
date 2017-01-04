From iris.proofmode Require Import tactics.
From lrust.lang Require Import heap memcpy.
From lrust.lifetime Require Import borrow frac_borrow.
From lrust.typing Require Export uninit uniq_bor shr_bor own sum.
From lrust.typing Require Import lft_contexts type_context programs product.

Section case.
  Context `{typeG Σ}.

  (* FIXME : the doc does not give [p +ₗ #(S (ty.(ty_size))) ◁ ...]. *)
  Lemma type_case_own E L C T p n tyl el :
    Forall2 (λ ty e,
      typed_body E L C ((p +ₗ #0 ◁ own n (uninit 1)) :: (p +ₗ #1 ◁ own n ty) ::
         (p +ₗ #(S (ty.(ty_size))) ◁
            own n (uninit (list_max (map ty_size tyl) - ty_size ty))) :: T) e ∨
      typed_body E L C ((p ◁ own n (sum tyl)) :: T) e) tyl el →
    typed_body E L C ((p ◁ own n (sum tyl)) :: T) (case: !p of el).
  Proof.
    iIntros (Hel tid qE) "#HEAP #LFT Hna HE HL HC HT". wp_bind p.
    rewrite tctx_interp_cons. iDestruct "HT" as "[Hp HT]".
    iApply (wp_hasty with "Hp"). iIntros (v Hv) "Hp".
    iDestruct "Hp" as (l) "[EQ [H↦ Hf]]". iDestruct "EQ" as %[=->].
    iDestruct "H↦" as (vl) "[H↦ Hown]".
    iDestruct "Hown" as (i vl' vl'') "(>% & >EQlen & Hown)". subst.
    simpl ty_size. iDestruct "EQlen" as %[=EQlen]. rewrite -EQlen. simpl length.
    rewrite -Nat.add_1_l app_length -!freeable_sz_split
            heap_mapsto_vec_cons heap_mapsto_vec_app.
    iDestruct "H↦" as "(H↦i & H↦vl' & H↦vl'')".
    iDestruct "Hf" as "(Hfi & Hfvl' & Hfvl'')".
    rewrite nth_lookup.
    destruct (tyl !! i) as [ty|] eqn:EQty; last iDestruct "Hown" as ">[]".
    edestruct @Forall2_lookup_l as (e & He & Hety); eauto.
    wp_read. iApply wp_case; [lia|by rewrite Nat2Z.id|]. iNext.
    destruct Hety as [Hety|Hety]; iApply (Hety with "HEAP LFT Hna HE HL HC");
      rewrite !tctx_interp_cons !tctx_hasty_val' /= ?Hv //; iFrame "HT".
    - iDestruct (ty.(ty_size_eq) with "Hown") as %<-.
      iSplitL "H↦i Hfi"; last iSplitR "H↦vl'' Hfvl''".
      + rewrite shift_loc_0. iExists _. iFrame. iSplit. done. iExists [ #i].
        rewrite heap_mapsto_vec_singleton.
        iFrame. iExists [_], []. auto.
      + iExists _. iFrame. iSplit. done. iExists _. iFrame.
      + rewrite -EQlen app_length minus_plus uninit_sz -(shift_loc_assoc_nat _ 1).
        iExists _. iFrame. iSplit. done. iExists _. iFrame. rewrite uninit_own. auto.
    - iExists _. iSplit. done.
      assert (EQf:=freeable_sz_split n 1). simpl in EQf. rewrite -EQf. clear EQf.
      rewrite -EQlen app_length -freeable_sz_split. iFrame.
      iExists (#i :: vl' ++ vl''). iNext.
      rewrite heap_mapsto_vec_cons heap_mapsto_vec_app.
      iFrame. iExists i, vl', vl''. rewrite /= app_length nth_lookup EQty. auto.
  Qed.

  Lemma type_case_own' E L C T T' p n tyl el :
    tctx_extract_hasty E L p (own n (sum tyl)) T T' →
    Forall2 (λ ty e,
      typed_body E L C ((p +ₗ #0 ◁ own n (uninit 1)) :: (p +ₗ #1 ◁ own n ty) ::
         (p +ₗ #(S (ty.(ty_size))) ◁
            own n (uninit (list_max (map ty_size tyl) - ty_size ty))) :: T') e ∨
      typed_body E L C ((p ◁ own n (sum tyl)) :: T') e) tyl el →
    typed_body E L C T (case: !p of el).
  Proof. unfold tctx_extract_hasty. intros ->. apply type_case_own. Qed.

  Lemma type_case_uniq E L C T p κ tyl el :
    lctx_lft_alive E L κ →
    Forall2 (λ ty e,
      typed_body E L C ((p +ₗ #1 ◁ &uniq{κ}ty) :: T) e ∨
      typed_body E L C ((p ◁ &uniq{κ}sum tyl) :: T) e) tyl el →
    typed_body E L C ((p ◁ &uniq{κ}sum tyl) :: T) (case: !p of el).
  Proof.
    iIntros (Halive Hel tid qE) "#HEAP #LFT Hna HE HL HC HT". wp_bind p.
    rewrite tctx_interp_cons. iDestruct "HT" as "[Hp HT]".
    iApply (wp_hasty with "Hp"). iIntros (v Hv) "Hp".
    iDestruct "Hp" as (l P) "[[EQ HP] Hb]". iDestruct "EQ" as %[=->].
    iMod (bor_iff with "LFT HP Hb") as "Hb". done.
    iMod (Halive with "HE HL") as (q) "[Htok Hclose]". done.
    iMod (bor_acc_cons with "LFT Hb Htok") as "[H↦ Hclose']". done.
    iDestruct "H↦" as (vl) "[H↦ Hown]".
    iDestruct "Hown" as (i vl' vl'') "(>% & >EQlen & Hown)". subst.
    iDestruct "EQlen" as %[=EQlen].
    rewrite heap_mapsto_vec_cons heap_mapsto_vec_app nth_lookup.
    iDestruct "H↦" as "(H↦i & H↦vl' & H↦vl'')".
    destruct (tyl !! i) as [ty|] eqn:EQty; last iDestruct "Hown" as ">[]".
    edestruct @Forall2_lookup_l as (e & He & Hety); eauto.
    wp_read. iApply wp_case; [lia|by rewrite Nat2Z.id|]. iNext.
    iDestruct (ty.(ty_size_eq) with "Hown") as %EQlenvl'.
    destruct Hety as [Hety|Hety].
    - iMod ("Hclose'" $! (shift_loc l 1 ↦∗: ty.(ty_own) tid)%I
            with "[H↦vl' Hown] [H↦i H↦vl'']") as "[Hb Htok]".
      { iExists vl'. iFrame. }
      { iIntros "!>Hown". iDestruct "Hown" as (vl'2) "[H↦ Hown]".
        iExists (#i::vl'2++vl''). iIntros "!>". iNext.
        iDestruct (ty.(ty_size_eq) with "Hown") as %EQlenvl'2.
        rewrite heap_mapsto_vec_cons heap_mapsto_vec_app EQlenvl' EQlenvl'2.
        iFrame. iExists _, _, _. iSplit. by auto.
        rewrite /= -EQlen !app_length EQlenvl' EQlenvl'2 nth_lookup EQty /=. auto. }
      iMod ("Hclose" with "Htok") as "[HE HL]".
      iApply (Hety with "HEAP LFT Hna HE HL HC").
      rewrite !tctx_interp_cons !tctx_hasty_val' /= ?Hv //. iFrame "HT".
      iExists _, _. iFrame. iSplit. done. iSplit; iIntros "!>!#$".
    - iMod ("Hclose'" with "* [H↦i H↦vl' H↦vl'' Hown] []") as "[Hb Htok]";
        [|by iIntros "!>$"|].
      { iExists (#i::vl'++vl'').
        rewrite heap_mapsto_vec_cons heap_mapsto_vec_app -EQlen. iFrame. iNext.
        iExists i, vl', vl''. rewrite nth_lookup EQty. auto. }
      iMod ("Hclose" with "Htok") as "[HE HL]".
      iApply (Hety with "HEAP LFT Hna HE HL HC").
      rewrite !tctx_interp_cons !tctx_hasty_val' /= ?Hv //. iFrame "HT".
      iExists _, _. iFrame. iSplit. done. iSplit; iIntros "!>!#$".
  Qed.

  Lemma type_case_uniq' E L C T T' p κ tyl el :
    tctx_extract_hasty E L p (&uniq{κ}sum tyl) T T' →
    lctx_lft_alive E L κ →
    Forall2 (λ ty e,
      typed_body E L C ((p +ₗ #1 ◁ &uniq{κ}ty) :: T') e ∨
      typed_body E L C ((p ◁ &uniq{κ}sum tyl) :: T') e) tyl el →
    typed_body E L C T (case: !p of el).
  Proof. unfold tctx_extract_hasty. intros ->. apply type_case_uniq. Qed.

  Lemma type_case_shr E L C T p κ tyl el:
    lctx_lft_alive E L κ →
    Forall2 (λ ty e,
      typed_body E L C ((p +ₗ #1 ◁ &shr{κ}ty) :: T) e ∨
      typed_body E L C ((p ◁ &shr{κ}sum tyl) :: T) e) tyl el →
    typed_body E L C ((p ◁ &shr{κ}sum tyl) :: T) (case: !p of el).
  Proof.
    iIntros (Halive Hel tid qE) "#HEAP #LFT Hna HE HL HC HT". wp_bind p.
    rewrite tctx_interp_cons. iDestruct "HT" as "[Hp HT]".
    iApply (wp_hasty with "Hp"). iIntros (v Hv) "Hp".
    iDestruct "Hp" as (l) "[EQ Hl]". iDestruct "EQ" as %[=->].
    iDestruct "Hl" as (i) "[#Hb Hshr]".
    iMod (Halive with "HE HL") as (q) "[Htok Hclose]". done.
    iMod (frac_bor_acc with "LFT Hb Htok") as (q') "[[H↦i H↦vl''] Hclose']". done.
    rewrite nth_lookup.
    destruct (tyl !! i) as [ty|] eqn:EQty; last iDestruct "Hshr" as "[]".
    edestruct @Forall2_lookup_l as (e & He & Hety); eauto.
    wp_read. iApply wp_case; [lia|by rewrite Nat2Z.id|]. iNext.
    iMod ("Hclose'" with "[$H↦i $H↦vl'']") as "Htok".
    iMod ("Hclose" with "Htok") as "[HE HL]".
    destruct Hety as [Hety|Hety]; iApply (Hety with "HEAP LFT Hna HE HL HC");
      rewrite !tctx_interp_cons !tctx_hasty_val' /= ?Hv //; iFrame "HT".
    - iExists _. auto.
    - iExists _. iSplit. done. iExists i. rewrite nth_lookup EQty /=. auto.
  Qed.

  Lemma type_case_shr' E L C T p κ tyl el :
    (p ◁ &shr{κ}sum tyl)%TC ∈ T →
    lctx_lft_alive E L κ →
    Forall2 (λ ty e, typed_body E L C ((p +ₗ #1 ◁ &shr{κ}ty) :: T) e) tyl el →
    typed_body E L C T (case: !p of el).
  Proof.
    intros. rewrite ->copy_elem_of_tctx_incl; last done; last apply _.
    apply type_case_shr; first done. eapply Forall2_impl; first done. auto.
  Qed.

  Lemma type_sum_assign {E L} (i : nat) tyl ty1 ty2 ty p1 p2 :
    tyl !! i = Some ty →
    typed_write E L ty1 (sum tyl) ty2 →
    typed_instruction E L [p1 ◁ ty1; p2 ◁ ty] (p1 <-{i} p2) (λ _, [p1 ◁ ty2]%TC).
  Proof.
    iIntros (Hty Hw ??) "#HEAP #LFT $ HE HL Hp".
    rewrite tctx_interp_cons tctx_interp_singleton.
    iDestruct "Hp" as "[Hp1 Hp2]". iDestruct (closed_hasty with "Hp1") as "%".
    iDestruct (closed_hasty with "Hp2") as "%". wp_bind p1.
    iApply (wp_hasty with "Hp1"). iIntros (v1 Hv1) "Hty1".
    iMod (Hw with "LFT HE HL Hty1") as (l vl) "(H & H↦ & Hw)"=>//=.
    destruct vl as [|? vl]; iDestruct "H" as %[[= Hlen] ->].
    rewrite heap_mapsto_vec_cons. iDestruct "H↦" as "[H↦0 H↦vl]".
    wp_write. iApply wp_seq. done. iNext. wp_bind p1.
    iApply (wp_wand with "[]"); first by iApply (wp_eval_path).
    iIntros (? ->). wp_op. wp_bind p2. iApply (wp_hasty with "Hp2").
    iIntros (v2 Hv2) "Hty2". iDestruct (ty_size_eq with "Hty2") as %Hlenty.
    destruct vl as [|? vl].
    { exfalso. revert i Hty. clear - Hlen Hlenty. induction tyl=>//= -[|i] /=.
      - intros [= ->]. simpl in *. lia.
      - apply IHtyl. simpl in *. lia. }
    rewrite heap_mapsto_vec_cons. iDestruct "H↦vl" as "[H↦ H↦vl]". wp_write.
    rewrite tctx_interp_singleton tctx_hasty_val' //. iApply "Hw". iNext.
    iExists (_::_::_). rewrite !heap_mapsto_vec_cons. iFrame.
    iExists i, [_], _. rewrite -Hlen nth_lookup Hty. auto.
  Qed.

  Lemma type_sum_assign_unit {E L} (i : nat) tyl ty1 ty2 p :
    tyl !! i = Some unit →
    typed_write E L ty1 (sum tyl) ty2 →
    typed_instruction E L [p ◁ ty1] (p <-{i} ☇) (λ _, [p ◁ ty2]%TC).
  Proof.
    iIntros (Hty Hw ??) "#HEAP #LFT $ HE HL Hp". rewrite tctx_interp_singleton.
    wp_bind p. iApply (wp_hasty with "Hp"). iIntros (v Hv) "Hty".
    iMod (Hw with "LFT HE HL Hty") as (l vl) "(H & H↦ & Hw)". done.
    simpl. destruct vl as [|? vl]; iDestruct "H" as %[[= Hlen] ->].
    rewrite heap_mapsto_vec_cons. iDestruct "H↦" as "[H↦0 H↦vl]".
    wp_write. rewrite tctx_interp_singleton tctx_hasty_val' //.
    iApply "Hw". iModIntro. iExists (_::_). rewrite heap_mapsto_vec_cons. iFrame.
    iExists i, [], _. rewrite -Hlen nth_lookup Hty. auto.
  Qed.

  Lemma type_sum_memcpy {E L} (i : nat) tyl ty1 ty1' ty2 ty2' ty p1 p2 :
    tyl !! i = Some ty →
    typed_write E L ty1 (sum tyl) ty1' →
    typed_read E L ty2 ty ty2' →
    typed_instruction E L [p1 ◁ ty1; p2 ◁ ty2]
               (p1 <⋯{i} !{ty.(ty_size)}p2) (λ _, [p1 ◁ ty1'; p2 ◁ ty2']%TC).
  Proof.
    iIntros (Hty Hw Hr ??) "#HEAP #LFT Htl [HE1 HE2] [HL1 HL2] Hp".
    rewrite tctx_interp_cons tctx_interp_singleton.
    iDestruct "Hp" as "[Hp1 Hp2]". iDestruct (closed_hasty with "Hp1") as "%".
    iDestruct (closed_hasty with "Hp2") as "%". wp_bind p1.
    iApply (wp_hasty with "Hp1"). iIntros (v1 Hv1) "Hty1".
    iMod (Hw with "LFT HE1 HL1 Hty1") as (l1 vl1) "(H & H↦ & Hw)"=>//=.
    destruct vl1 as [|? vl1]; iDestruct "H" as %[[= Hlen] ->].
    rewrite heap_mapsto_vec_cons. iDestruct "H↦" as "[H↦0 H↦vl1]". wp_write.
    iApply wp_seq. done. iNext. wp_bind p1.
    iApply (wp_wand with "[]"); first by iApply (wp_eval_path). iIntros (? ->).
    wp_op. wp_bind p2. iApply (wp_hasty with "Hp2"). iIntros (v2 Hv2) "Hty2".
    iMod (Hr with "LFT Htl HE2 HL2 Hty2") as (l2 vl2 q) "(% & H↦2 & Hty & Hr)"=>//=. subst.
    assert (ty.(ty_size) ≤ length vl1).
    { revert i Hty. rewrite Hlen. clear. induction tyl=>//= -[|i] /=.
      - intros [= ->]. lia.
      - specialize (IHtyl i). intuition lia. }
    rewrite -(take_drop (ty.(ty_size)) vl1) heap_mapsto_vec_app.
    iDestruct "H↦vl1" as "[H↦vl1 H↦pad]".
    iAssert (▷ ⌜length vl2 = ty.(ty_size)⌝)%I with "[#]" as ">%". by rewrite -ty_size_eq.
    iApply wp_fupd. iApply (wp_memcpy with "[$HEAP $H↦vl1 $H↦2]"); try done.
    { rewrite take_length. lia. }
    iNext; iIntros "[H↦vl1 H↦2]".
    rewrite tctx_interp_cons tctx_interp_singleton !tctx_hasty_val' //.
    iMod ("Hr" with "H↦2") as "($ & $ & $ & $)". iApply "Hw". iNext.
    rewrite split_sum_mt /is_pad. iExists i. rewrite nth_lookup Hty. iFrame.
    iSplitL "H↦pad".
    - rewrite (shift_loc_assoc_nat _ 1) take_length Nat.min_l; last lia.
      iExists _. iFrame. rewrite /= drop_length. iPureIntro. lia.
    - iExists _. iFrame.
  Qed.
End case.