From sflib Require Import sflib.
From Paco Require Import paco.
Require Import Coq.Classes.RelationClasses Lia Program.
From iris Require Import bi.big_op.
From Fairness Require Import pind Axioms ITreeLib Red TRed IRed2 WFLibLarge.
From Fairness Require Import FairBeh Mod Linking.
From Fairness Require Import treiber.Code.
From Fairness Require Import PCM IProp IPM IPropAux.
From Fairness Require Import IndexedInvariants OpticsInterp SimWeakest.
From Fairness Require Import TemporalLogic SCMemSpec ghost_var ghost_map.

Record maybe_null_ptr := {
  ptr :> SCMem.val;
  ptr_mabye_null : ptr = SCMem.val_null \/ (∃ (p : SCMem.pointer), ptr = SCMem.val_ptr p);
}.
Global Instance maybe_null_ptr_eq_dec : EqDecision maybe_null_ptr.
Proof.
  intros [p1 Pp1] [p2 Pp2].
  unfold Decision. destruct (decide (p1 = p2)) as [->|NEQ].
  - left. f_equal. apply proof_irrelevance.
  - right. intros H. apply NEQ. injection H. done.
Qed.

Definition to_mnp_null : maybe_null_ptr := {| ptr := SCMem.val_null; ptr_mabye_null := or_introl eq_refl |}.

Definition to_mnp_ptr ptr
  (IsPtr : (∃ (p : SCMem.pointer), ptr = SCMem.val_ptr p)) :=
  {| ptr := ptr; ptr_mabye_null := or_intror IsPtr |}.

Section SPEC.

  Context {src_state : Type}.
  Context {src_ident : Type}.
  Context {Client : Mod.t}.
  Context {gvs : list nat}.
  Context (treiberN : namespace) `{DISJ: (↑N_state_tgt :coPset) ## (↑treiberN : coPset)}.
  Notation tgt_state := (OMod.closed_state Client (SCMem.mod gvs)).
  Notation tgt_ident := (OMod.closed_ident Client (SCMem.mod gvs)).

  Local Instance STT : StateTypes := Build_StateTypes src_state tgt_state src_ident tgt_ident.

  Context `{sub : @SRA.subG Γ Σ}.
  Context {TLRASs : TLRAs_small STT Γ}.
  Context {TLRAS : TLRAs STT Γ Σ}.

  Context {HasMEMRA: @GRA.inG memRA Γ}.
  Context {HasAuthExcl : @GRA.inG (ghost_varURA (list SCMem.val)) Γ}.
  Context {HasGhostMap : @GRA.inG (ghost_mapURA nat maybe_null_ptr) Γ}.

  Ltac red_tl_all := red_tl_every; red_tl_memra; red_tl_ghost_var_ura; red_tl_ghost_map_ura.

  Definition to_val (mnp : maybe_null_ptr) : SCMem.val :=
    ptr mnp.

  Fixpoint phys_list n (l : maybe_null_ptr) (L : list SCMem.val) : sProp n := (
    match L with
    | [] => ⌜to_val l = SCMem.val_null⌝
    | v::tL => ∃ (p : τ{SCMem.pointer}) (r : τ{maybe_null_ptr}), ⌜to_val l = SCMem.val_ptr p⌝ ∗ (l ↦∗□ [(to_val r); v]) ∗ (phys_list n r tL)
    end
  )%S.

  Definition TStack n γs St : sProp n := (
    s_ghost_var γs (1/2) St
  )%S.

  Lemma TStack_agree n γs St1 St2 :
    ⟦ TStack n γs St1, n ⟧ -∗ ⟦ TStack n γs St2, n ⟧ -∗ ⌜St1 = St2⌝.
  Proof.
    unfold TStack. red_tl_all. iIntros "H1 H2".
    iDestruct (ghost_var_agree with "H1 H2") as %->. done.
  Qed.

  Lemma TStack_update n γs St1 St2 St :
    ⟦ TStack n γs St1, n ⟧ -∗ ⟦ TStack n γs St2, n ⟧ ==∗ ⟦ TStack n γs St, n ⟧ ∗ ⟦ TStack n γs St, n ⟧.
  Proof.
    unfold TStack. red_tl_all. iIntros "H1 H2".
    iApply (ghost_var_update_halves with "H1 H2").
  Qed.

  Definition LInv (n k γs : nat) (h : maybe_null_ptr) (m : gmap nat maybe_null_ptr) : sProp n  := (
    s_ghost_map_auth γs 1 m ∗
    [∗ n, maybe_null_ptr map] i ↦ p ∈ m, (
      if (decide (h=p)) then
        emp
      else
        ◇[k](0,1)
    )
  )%S.

  Definition Inv (n : nat) (s : SCMem.val) (k γs γl : nat) : sProp n := (
    ∃ (h : τ{maybe_null_ptr}) (L : τ{list SCMem.val}) (m : τ{gmap nat maybe_null_ptr,n}),
      s ↦ (to_val h) ∗ s_ghost_var γs (1/2) L ∗
      phys_list n h L ∗ LInv n k γl h m
  )%S.

  Definition IsT n l a s k γs : sProp n := (
    ∃ (γl : τ{nat,n}), ◆[k,l,a] ∗ syn_inv n treiberN (Inv n s k γs γl)
  )%S.

  Global Instance IsT_persistent n l a s k γs :
    Persistent (⟦ IsT n l a s k γs, n⟧).
  Proof. unfold Persistent,IsT. red_tl.
    iIntros "[%γl H]". iExists γl. red_tl.
    rewrite red_syn_inv.
    iDestruct "H" as "#$".
  Qed.

  Lemma Inv_unfold n s k γs γl :
    (⟦ Inv n s k γs γl, n ⟧) -∗
    (∃ (h : τ{maybe_null_ptr,n}) (L : τ{list SCMem.val,n}) (m : τ{gmap nat maybe_null_ptr,n}),
      (s ↦ (to_val h)) ∗ ghost_var γs (1/2) L ∗
      ⟦ (phys_list n h L), n⟧ ∗ ⟦ LInv n k γl h m, n⟧).
  Proof.
    unfold Inv. iIntros "Inv".
    repeat (red_tl; iDestruct "Inv" as "[% Inv]").
    red_tl_all. eauto.
  Qed.

  Lemma Inv_fold n s k γs γl h L m :
    (s ↦ (to_val h)) -∗ ghost_var γs (1/2) L -∗
    ⟦ (phys_list n h L), n⟧ -∗ ⟦ LInv n k γl h m, n⟧
    -∗ (⟦ Inv n s k γs γl, n ⟧).
  Proof.
    unfold Inv. iIntros "? ? ? ?".
    repeat (red_tl; iExists _).
    red_tl_all. iFrame.
  Qed.

  Lemma LInv_unfold n k γs h m :
    (⟦ LInv n k γs h m, n ⟧) -∗
    ghost_map_auth γs 1 m ∗
    [∗ map] a ∈ m,
      if decide (h = a) then
          emp
        else
          ◇[k](0, 1)
    .
  Proof.
    unfold LInv. red_tl_all. iIntros "[$ H]".
    rewrite red_syn_big_sepM.
    iApply (big_sepM_mono with "H").
    ii. des_ifs.
  Qed.

  Lemma LInv_fold n k γl h m :
    ghost_map_auth γl 1 m -∗
    ([∗ map] a ∈ m,
      if decide (h = a) then
          emp
        else
          ◇[k](0, 1)
        )
    -∗ (⟦ LInv n k γl h m, n ⟧).
  Proof.
    unfold LInv. red_tl_all. iIntros "$ H".
    rewrite red_syn_big_sepM.
    iApply (big_sepM_mono with "H").
    ii. des_ifs.
  Qed.


  Lemma phys_list_unfold n l L :
    (⟦ phys_list n l L, n ⟧) -∗
    match L with
    | [] => ⌜to_val l = SCMem.val_null⌝
    | v::tL => ∃ (p : τ{SCMem.pointer,n}) (r : τ{maybe_null_ptr,n}), ⌜to_val l = SCMem.val_ptr p⌝ ∗ (l ↦∗□ [(to_val r); v]) ∗ (⟦phys_list n r tL,n⟧)
    end.
  Proof.
    iIntros "H". des_ifs. simpl.
    red_tl_all; iDestruct "H" as "[%x H]".
    red_tl_all; iDestruct "H" as "[%r H]".
    red_tl_all; iDestruct "H" as "[%EQ [(l.n↦ & l.d↦ & _) Phys]]".
    iExists _,_. iFrame. done.
  Qed.

  Lemma phys_list_fold n l L :
    (match L with
    | [] => ⌜to_val l = SCMem.val_null⌝
    | v::tL => ∃ (p : τ{SCMem.pointer,n}) (r : τ{maybe_null_ptr,n}), ⌜to_val l = SCMem.val_ptr p⌝ ∗ (l ↦∗□ [(to_val r); v]) ∗ (⟦phys_list n r tL,n⟧)
    end) -∗
    ⟦ phys_list n l L, n ⟧.
  Proof.
    iIntros "H". des_ifs. simpl.
    red_tl_all; iDestruct "H" as "[%x [%r [%EQ [(l.n↦ & l.d↦ & _) Phys]]]]".
    red_tl_all. iExists x. red_tl_all. iExists r.
    red_tl_all. iFrame. done.
  Qed.

  Lemma phys_list_get_head n l L :
    ⟦ phys_list n l L, n ⟧ -∗
    □ if (decide (to_val l = SCMem.val_null)) then
        emp
      else (∃ (r : τ{maybe_null_ptr,n}) (h : τ{SCMem.val,n}),
                 (l ↦∗□ [(to_val r); h]))
    .
  Proof.
    iIntros "H". iDestruct (phys_list_unfold with "H") as "H". destruct L; try done.
    all: case_decide; try done.
    - iDestruct "H" as %EQ. done.
    - iDestruct "H" as (p r) "[%EQ [#H _]]".
      red_tl_all. iExists r, v. iFrame "H".
  Qed.

  Lemma alloc_Treiber n s l a :
    ⊢ s ↦ SCMem.val_null =|S n|={∅}=∗ ∃ k γs, ⟦IsT n l a s k γs,n⟧ ∗ ⟦TStack n γs [],n⟧ ∗ ◇[k](l,a).
  Proof.
    iIntros "s↦".
    iMod (alloc_obligation_fine l a) as (k) "(#Ob_kb & PCs & _)".
    iMod ghost_map_alloc_empty as (γl) "M".
    iMod (ghost_var_alloc []) as (γs) "V".
    iEval (rewrite -Qp.half_half) in "V".
    iEval (rewrite ghost_var_split) in "V".
    iDestruct "V" as "[VI VS]".
    iMod (FUpd_alloc _ _ _ n (treiberN) (Inv n s k γs γl) with "[VI s↦ M]") as "#Inv"; [lia| |].
    { iApply (Inv_fold _ _ _ _ _ to_mnp_null with "s↦ VI [] [M]").
      - iApply phys_list_fold. done.
      - iApply (LInv_fold with "M"). done.
    }
    iModIntro. iExists _,_. iFrame. unfold IsT,TStack. red_tl_all.
    iFrame. iExists _. red_tl. rewrite red_syn_inv. iFrame "#".
  Qed.

  Lemma Treiber_push_spec {n} (Q : SCMem.val → sProp n) (P : sProp n) tid :
    ∀ s k γs val l a (ds : list (nat * nat * sProp n)),
    ⊢ [@ tid, n, ⊤ @]
          ⧼⟦(
            (syn_tgt_interp_as n sndl (fun m => s_memory_black m))
            ∗ (⤉ IsT n l a s k γs)
            ∗ (⤉ Duty(tid) ds)
            ∗ (⤉ P)
            ∗ (∀ (St : τ{list SCMem.val, 1+n}), (⤉ (TStack n γs (St : list SCMem.val) ∗ P))
                  =|1+n|={⊤ ∖ ↑treiberN}=∗ (⤉ (TStack n γs (val::St : list SCMem.val) ∗ Q val))
              )
            ∗ ◇[k](1,1)
            ∗ ◇{List.map fst ds}(2+l,2+a)
            )%S, 1+n⟧⧽
            (OMod.close_itree Client (SCMem.mod gvs) (TreiberStack.push (s,val)))
          ⧼_, ⟦(
            (⤉ (Q val ∗ Duty(tid) ds))
            )%S, 1+n⟧⧽
  .
  Proof.
    ii. iStartTriple. red_tl_all.
    unfold IsT,TStack. rewrite red_syn_tgt_interp_as. red_tl. simpl.
    iIntros "(#Mem & IsT & Duty & P & AU & Ob_ks & PCS) Post".
    iDestruct "IsT" as (γl) "IsT".
    red_tl. rewrite red_syn_inv. iDestruct "IsT" as "#[Ob_kb IsT]".

    iMod (pcs_decr _ _ 1 (1+a) with "PCS") as "[Ys PCS]"; [lia|].
    iMod (pcs_decr _ _ 1 a with "PCS") as "[PCS CCS]"; [lia|].
    iMod (pcs_drop _ _ 1 ltac:(lia) 1 100 with "Ys") as "Ys"; [lia|].
    iMod (ccs_make_fine _ _ _ _ 2 with "[$Ob_kb $CCS]") as "CCS".

    iEval (unfold TreiberStack.push). rred2r.

    iMod ((pcs_decr _ _ 99 1) with "Ys") as "[Ys Y]"; [lia|].
    iApply (wpsim_yieldR with "[$Duty $Y]"); [lia|].
    iIntros "Duty _". rred2r.

    iApply (SCMem_alloc_fun_spec with "[$Mem] [-]"); [lia|set_solver|].
    iIntros (node) "(n.n↦ & n.d↦ & _)".
    rred2r. iApply wpsim_tauR. rred2r.

    iMod ((pcs_decr _ _ 98 1) with "Ys") as "[Ys Y]"; [lia|].
    iApply (wpsim_yieldR with "[$Y $Duty]"); [lia|].
    iIntros "Duty _". rred2r.

    iApply (SCMem_store_fun_spec with "[$Mem $n.d↦] [-]"); [lia|set_solver|].
    iIntros (?) "n.d↦". rred2r. iApply wpsim_tauR. rred2r.

    move: (SCMem.val_nat 0) => next.

    iRevert "n.n↦ Post Duty Ys AU P n.d↦ Ob_ks". iRevert (next). iRevert "PCS".

    iMod (ccs_ind2 with "CCS [-]") as "Ind".
    2:{ iIntros "PCS". destruct l; last first.
        - iMod (pcs_drop _ _ 1 ltac:(auto) 2 1 with "PCS") as "PCS"; [lia|].
          iApply ("Ind" with "PCS").
        - iApply ("Ind" with "PCS").
    }

    iModIntro. iExists 0. iIntros "IH !> Pcs %next n.n↦ Post Duty Ys AU P n.d↦ Ob_ks".
    iEval (rewrite unfold_iter_eq). rred2r.
    iMod ((pcs_decr _ _ 97 1) with "Ys") as "[Ys Y]"; [lia|].

    iApply (wpsim_yieldR with "[$Y $Duty]"); [lia|].
    iIntros "Duty _". rred2r.

    iInv "IsT" as "Inv" "Close". simpl.
    iDestruct (Inv_unfold with "Inv") as (h L m) "(s↦ & γs & Phys & LInv)".
    iApply (SCMem_load_fun_spec with "[$Mem $s↦] [-]"); [lia|solve_ndisj|].
    iIntros (load_v) "[%EQ s↦]". subst.
    (* Get proof that h is live for future use. *)
    iDestruct (phys_list_get_head with "Phys") as "#h↦□".

    (* Register this thread to the current waiting list for h. *)
    iDestruct (LInv_unfold with "LInv") as "[GMap LivC]".
    set (i := fresh (dom m)).
    iMod (ghost_map_insert i h with "[$GMap]") as "[GMap i↪]".
    { apply not_elem_of_dom. apply is_fresh. }

    (* Close Invs *)
    iDestruct (LInv_fold with "GMap [LivC]") as "LInv".
    { rewrite big_sepM_insert; last first.
      { apply not_elem_of_dom. apply is_fresh. }
      iFrame. iClear "h↦□". case_decide; done.
    }
    iDestruct (Inv_fold with "s↦ γs Phys LInv") as "Inv".
    iMod ("Close" with "Inv") as "_". move: i => i. clear dependent L m rv. rred2r.

    iApply wpsim_tauR. rred2r.

    iMod ((pcs_decr _ _ 96 1) with "Ys") as "[Ys Y]"; [lia|].
    iApply (wpsim_yieldR with "[$Y $Duty]"); [lia|].
    iIntros "Duty _". rred2r.

    iApply (SCMem_store_fun_spec with "[$Mem $n.n↦] [-]"); [lia|solve_ndisj|].
    iIntros (?) "n.n↦". rred2r. iApply wpsim_tauR. rred2r.

    iMod ((pcs_decr _ _ 95 1) with "Ys") as "[Ys Y]"; [lia|].
    iApply (wpsim_yieldR with "[$Y $Duty]"); [lia|].
    iIntros "Duty _". rred2r.

    iMod ((pcs_decr _ _ 94 1) with "Ys") as "[Ys Y]"; [lia|].

    iInv "IsT" as "Inv" "Close". simpl.
    iDestruct (Inv_unfold with "Inv") as (h' L m) "(s↦ & γs & Phys & LInv)".
    iDestruct (phys_list_get_head with "Phys") as "#h'↦□".
    destruct (decide (h = h')) as [<-|NEQ].
    { (* Equal, CAS success *)
      iApply (SCMem_cas_loc_fun_spec_gen with "[$Mem $s↦ h↦□ h'↦□] [-]"); [lia|solve_ndisj| |].
      { des_ifs.
        iDestruct "h↦□" as (??) "[h↦□ _]".
        iSplit; iExists _; iFrame "h↦□".
      }
      iClear "h↦□ h'↦□".
      iIntros (b) "POST".
      iDestruct "POST" as (u) "(%EQ & s↦ & _ & _)".
      des_ifs. destruct EQ as [-> ->].
      iSpecialize ("AU" $! L).
      iEval (red_tl) in "AU".
      iEval (rewrite red_syn_fupd) in "AU".
      iEval (red_tl_all) in "AU".
      rred2r. iApply wpsim_tauR. rred2r.

      (* Update logical stack state. *)
      iMod ("AU" with "[$γs $P]") as "[γs Q]".

      (* Update physical stack state. *)
      iMod (SCMem.points_to_persist with "n.n↦") as "#n.n↦".
      iMod (SCMem.points_to_persist with "n.d↦") as "#n.d↦".
      iAssert (⌜∃ p : τ{SCMem.pointer,n}, node = SCMem.val_ptr p⌝)%I as %IsPtr.
      { destruct node; try done. iPureIntro. eauto. }
      iAssert (⟦ phys_list n (to_mnp_ptr node IsPtr) (val::L), n⟧)%I with "[Phys]" as "Phys".
      { iApply phys_list_fold. simpl. des. iExists _,_. iFrame "∗#". done. }

      (* Update liveness invariant *)
      iDestruct (LInv_unfold with "LInv") as "[GMap LivC]".

      iDestruct (ghost_map_lookup with "GMap i↪") as "%Lookup_i".
      iMod (ghost_map_delete with "GMap i↪") as "GMap".

      (** Create a big_opM of ◇[k](0,1). *)
      iMod (pc_drop _ 0 1 ltac:(auto) (size (delete i m)) with "Ob_ks") as "Ob_ks"; [lia|].
      iAssert ([∗ map] _ ∈ delete i m, ◇[k](0,1))%I with "[Ob_ks]" as "Ob_ks".
      { set (m' := delete i m). move: m' => m'.
        iClear "Mem IsT n.n↦ n.d↦". clear.
        simpl in *.
        iInduction (m') as [|id op m NotIN] "IH" using map_ind.
        { done. }
        rewrite big_sepM_insert; [|done].
        rewrite map_size_insert_None; [|done].
        iDestruct (pc_split _ _ 1 (size m) with "Ob_ks") as "[$ Ob_ks]".
        iApply ("IH" with "Ob_ks").
      }

      (** Add it to the invariant. *)
      iDestruct (big_sepM_delete with "LivC") as "[_ LivC]"; [apply Lookup_i|].
      iDestruct (LInv_fold _ _ _ (to_mnp_ptr node IsPtr) with "GMap [LivC Ob_ks]") as "LInv".
      { iDestruct (big_sepM_sep_2 with "LivC Ob_ks") as "LivC".
        iApply (big_sepM_mono with "LivC").
        iIntros (i' p' Lookup_i') "[H C]". des_ifs.
      }

      iDestruct (Inv_fold with "[s↦] γs Phys LInv") as "Inv".
      { unfold to_val. iFrame. }
      iMod ("Close" with "Inv") as "_". rred2r.

      iApply (wpsim_yieldR with "[$Y $Duty]"); [lia|].
      iIntros "Duty _". rred2r. iApply wpsim_tauR. rred2r.
      iApply "Post". iFrame.
    }
    (* Different, CAS fail *)
    iApply (SCMem_cas_loc_fun_spec_gen with "[$Mem $s↦ h↦□ h'↦□] [-]"); [lia|solve_ndisj| |].
    { unfold to_val. des_ifs.
      1,3: iDestruct "h'↦□" as (??) "[h'↦□ _]".
      2,3: iDestruct "h↦□" as (??) "[h↦□ _]".
      all: iSplit; try done; iExists _; iFrame "#".
    }
    iClear "h↦□ h'↦□".
    iIntros (b) "POST".
    iDestruct "POST" as (u) "(%EQ & s↦ & _ & _)".
    des_ifs. all: destruct EQ as [-> ->].
    { exfalso. clear - e NEQ. unfold to_val in e.
      destruct h as [h Ph],h' as [h' Ph']. simpl in *. clarify.
      assert (Ph = Ph') as -> by apply proof_irrelevance. done.
    }

    (* Update ◇[k](0,1) to use for induction *)
    iDestruct (LInv_unfold with "LInv") as "[GMap LivC]".

    iDestruct (ghost_map_lookup with "GMap i↪") as "%Lookup_i".
    iMod (ghost_map_delete with "GMap i↪") as "GMap".

    iDestruct (big_sepM_delete with "LivC") as "[Ob_k LivC]"; [apply Lookup_i|].
    case_decide; [done|].
    red_tl. simpl.

    iDestruct (LInv_fold with "GMap LivC") as "LInv".
    iDestruct (Inv_fold with "s↦ γs Phys LInv") as "Inv".
    iMod ("Close" with "Inv") as "_". rred2r.

    iApply wpsim_tauR. rred2r. iApply wpsim_tauR.

    (* Do Induction *)
    iMod (pcs_drop _ _ 1 ltac:(auto) 1 98 with "[$Pcs]") as "Pcs"; [lia|].
    iMod ("IH" with "Ob_k n.n↦ Post Duty Pcs AU P n.d↦ Ob_ks") as "IH".
    iApply "IH".
  Qed.

  Lemma Treiber_pop_spec
        {n} (Q : (option SCMem.val) → sProp n) (P : sProp n) tid :
    ∀ s k γs l a (ds : list (nat * nat * sProp n)),
    ⊢ [@ tid, n, ⊤ @]
          ⧼⟦(
            (syn_tgt_interp_as n sndl (fun m => s_memory_black m))
            ∗ (⤉ IsT n l a s k γs)
            ∗ (⤉ Duty(tid) ds)
            ∗ (⤉ P)
            ∗ (∀ (St : τ{list SCMem.val, 1+n}), (⤉ (TStack n γs (St : list SCMem.val) ∗ P))
                  =|1+n|={⊤∖↑treiberN}=∗
                  match St with
                  | [] => (⤉ (TStack n γs ([] : list SCMem.val) ∗ Q None))
                  | h::t => (⤉ (TStack n γs t ∗ Q (Some h)))
                  end
              )
            ∗ ◇[k](1,1)
            ∗ ◇{List.map fst ds}(2+l,2+a)
            )%S, 1+n⟧⧽
            (OMod.close_itree Client (SCMem.mod gvs) (TreiberStack.pop s))
          ⧼rv, ⟦(
            (⤉ (Q rv ∗ Duty(tid) ds)) ∗
            match rv with
            | Some _ => emp
            | None => ◇[k](1,1)
            end
            )%S, 1+n⟧⧽
  .
  Proof.
    ii. iStartTriple. red_tl_all.
    unfold IsT,TStack. rewrite red_syn_tgt_interp_as. red_tl. simpl.
    iIntros "(#Mem & IsT & Duty & P & AU & Ob_ks & PCS) Post".
    iDestruct "IsT" as (γl) "IsT".
    red_tl. rewrite red_syn_inv. iDestruct "IsT" as "#[Ob_kb IsT]".

    iMod (pcs_decr _ _ 1 (1+a) with "PCS") as "[Ys PCS]"; [lia|].
    iMod (pcs_decr _ _ 1 a with "PCS") as "[PCS CCS]"; [lia|].
    iMod (pcs_drop _ _ 1 ltac:(lia) 1 102 with "Ys") as "Ys"; [lia|].
    iMod (ccs_make_fine _ _ _ _ 2 with "[$Ob_kb $CCS]") as "CCS".

    iEval (unfold TreiberStack.pop). rred2r.

    iMod ((pcs_decr _ _ 101 1) with "Ys") as "[Ys Y]"; [lia|].
    iApply (wpsim_yieldR with "[$Duty $Y]"); [lia..|].
    iIntros "Duty _". rred2r.

    iApply wpsim_tauR. rred2r.

    iRevert "Post Duty Ys AU P Ob_ks". iRevert "PCS".

    iMod (ccs_ind2 with "CCS [-]") as "Ind".
    2:{ iIntros "PCS". destruct l; last first.
        - iMod (pcs_drop _ _ 1 ltac:(auto) 2 1 with "PCS") as "PCS"; [lia|].
        iApply ("Ind" with "PCS").
        - iApply ("Ind" with "PCS").
    }

    iModIntro. iExists 0. iIntros "IH !> PCS Post Duty Ys AU P Ob_ks".
    iEval (rewrite unfold_iter_eq). rred2r.

    iMod ((pcs_decr _ _ 100 1) with "Ys") as "[Ys Y]"; [lia|].
    iApply (wpsim_yieldR with "[$Duty $Y]"); [lia..|].
    iIntros "Duty _". rred2r.

    iInv "IsT" as "Inv" "Close". simpl.
    iDestruct (Inv_unfold with "Inv") as (h St m) "(s↦ & γs & Phys & LInv)".

    iApply (SCMem_load_fun_spec with "[$Mem $s↦] [-]"); [lia|solve_ndisj|].
    iIntros (?) "[%EQ s↦]".
    subst. rred2r. iApply wpsim_tauR. rred2r.
    iMod ((pcs_decr _ _ 99 1) with "Ys") as "[Ys Y]"; [lia|].

    destruct (decide (to_val h = to_mnp_null)) as [EQ|NEQ].
    { (* Head is null, so stack is empty. *)
      destruct h as [[h|h] EQh]; ss.
      subst. injection EQ as ->. simpl in *.
      iEval (rewrite phys_list_unfold) in "Phys".
      des_ifs; last first.
      { iDestruct "Phys" as (p r) "[%EQ _]". simpl in EQ. done. }
      iClear "Phys".
      iSpecialize ("AU" $! []). iEval (red_tl; rewrite red_syn_fupd; red_tl_all) in "AU".
      iMod ("AU" with "[$γs $P]") as "[γs Q]".
      iDestruct (Inv_fold with "[s↦] γs [] LInv") as "Inv".
      { unfold to_val. iFrame. }
      { iApply phys_list_fold. done. }
      iMod ("Close" with "Inv") as "_". rred2r.

      iApply (wpsim_yieldR with "[$Duty $Y]"); [lia..|].
      iIntros "Duty _". rred2r.

      iApply (SCMem_compare_fun_spec with "[Mem] [-]"); [|solve_ndisj| |].
      2:{ iApply (tgt_interp_as_equiv with "Mem"). clear.
          iStartProof. iIntros (m). simpl. red_tl_all. iSplit.
          - iIntros "$". iPureIntro. done.
          - iIntros "[$ _]".
        }
      1: lia.
      iIntros (?) "%EQ". destruct EQ as [EQ _]. des; last done.
      specialize (EQ EQh) as ->. rred2r.

      iApply (wpsim_tauR). rred2r.
      iApply "Post". red_tl_all. iFrame.
    }

    iDestruct (phys_list_get_head with "Phys") as "#h↦□".
    case_decide; [done|].
    iDestruct "h↦□" as (r d) "[h.n↦□ [h.d↦□ _]]".
    (* Update Linv by adding myself to the ghost map, in the same way as push *)

    iDestruct (LInv_unfold with "LInv") as "[GMap LivC]".
    set (i := fresh (dom m)).
    iMod (ghost_map_insert i h with "[$GMap]") as "[GMap i↪]".
    { apply not_elem_of_dom. apply is_fresh. }

    iDestruct (LInv_fold with "GMap [LivC]") as "LInv".
    { rewrite big_sepM_insert; last first.
      { apply not_elem_of_dom. apply is_fresh. }
      iFrame. case_decide; done.
    }

    iDestruct (Inv_fold with "s↦ γs Phys LInv") as "Inv".
    iMod ("Close" with "Inv") as "_". move: i=>i. clear dependent St m.

    iApply (wpsim_yieldR with "[$Duty $Y]"); [lia..|].
    iIntros "Duty _". rred2r.

    iApply (SCMem_compare_loc_null_fun_spec with "[$Mem $h.n↦□] [-]"); [lia|solve_ndisj|].
    iIntros (?) "[_ %EQ]". subst. rred2r.

    iApply (wpsim_tauR). rred2r.

    iMod ((pcs_decr _ _ 98 1) with "Ys") as "[Ys Y]"; [lia|].
    iApply (wpsim_yieldR with "[$Duty $Y]"); [lia..|].
    iIntros "Duty _". rred2r.

    iApply (SCMem_load_fun_spec with "[$Mem $h.n↦□] [-]"); [lia|solve_ndisj|].
    iIntros (?) "[%EQ _]". subst. rred2r.

    iApply (wpsim_tauR). rred2r.

    iMod ((pcs_decr _ _ 97 1) with "Ys") as "[Ys Y]"; [lia|].
    iApply (wpsim_yieldR with "[$Duty $Y]"); [lia..|].
    iIntros "Duty _". rred2r.

    iInv "IsT" as "Inv" "Close". simpl.
    iDestruct (Inv_unfold with "Inv") as (h' L m) "(s↦ & γs & Phys & LInv)".
    iDestruct (phys_list_get_head with "Phys") as "#h'↦□".
    destruct (decide (h = h')) as [<-|NEQhh'].
    { des_ifs. iDestruct "h'↦□" as (r' d') "[h'.n↦□ [h'.d↦□ _]]". subst.
      iDestruct (memory_ra_points_to_agree with "h.d↦□ h'.d↦□") as %<-.
      iDestruct (memory_ra_points_to_agree with "h.n↦□ h'.n↦□") as %<-.

      iDestruct (phys_list_unfold with "Phys") as "Phys".
      destruct L as [|v tL].
      { iDestruct "Phys" as %EQ. done. }
      iDestruct "Phys" as (? r_new) "[%EQ_p [[#h.n↦□' [#h.d↦□' _]] Phys]]".

      iDestruct (memory_ra_points_to_agree with "h.d↦□ h.d↦□'") as %<-.
      iDestruct (memory_ra_points_to_agree with "h.n↦□ h.n↦□'") as %->.
      clear r. iClear "h.n↦□' h.d↦□' h'.n↦□ h'.d↦□".

      (* Equal, CAS success *)
      iApply (SCMem_cas_loc_fun_spec_gen with "[$Mem $s↦] [-]"); [lia|solve_ndisj| |].
      { des_ifs.
        iSplit; iExists _; iFrame "h.n↦□".
      }
      iIntros (b) "POST".

      iDestruct "POST" as (u) "(%EQ & s↦ & _ & _)".
      des_ifs. destruct EQ as [-> ->].
      iSpecialize ("AU" $! (d::tL)).
      iEval (red_tl) in "AU".
      iEval (rewrite red_syn_fupd) in "AU".
      iEval (red_tl_all) in "AU".
      rred2r. iApply wpsim_tauR. rred2r.

      (* Update logical & physical stack state. *)
      iMod ("AU" with "[$γs $P]") as "[γs Q]".

      (* Update liveness invariant *)
      iDestruct (LInv_unfold with "LInv") as "[GMap LivC]".

      iDestruct (ghost_map_lookup with "GMap i↪") as "%Lookup_i".
      iMod (ghost_map_delete with "GMap i↪") as "GMap".

      (** Create a big_opM of ◇[k](0,1). *)
      iMod (pc_drop _ 0 1 ltac:(auto) (size (delete i m)) with "Ob_ks") as "Ob_ks"; [lia|].
      iAssert ([∗ map] _ ∈ delete i m, ◇[k](0,1))%I with "[Ob_ks]" as "Ob_ks".
      { set (m' := delete i m). move: m' => m'.
        iClear "Mem IsT h.n↦□ h.d↦□ Ob_kb". clear.
        simpl in *.
        iInduction (m') as [|id op m NotIN] "IH" using map_ind.
        { done. }
        rewrite big_sepM_insert; [|done].
        rewrite map_size_insert_None; [|done].
        iDestruct (pc_split _ _ 1 (size m) with "Ob_ks") as "[$ Ob_ks]".
        iApply ("IH" with "Ob_ks").
      }

      (** Add it to the invariant. *)
      iDestruct (big_sepM_delete with "LivC") as "[_ LivC]"; [apply Lookup_i|].
      iDestruct (LInv_fold _ _ _ r_new with "GMap [LivC Ob_ks]") as "LInv".
      { iDestruct (big_sepM_sep_2 with "LivC Ob_ks") as "LivC".
        iApply (big_sepM_mono with "LivC").
        iIntros (i' p' Lookup_i') "[H C]". des_ifs.
      }

      iDestruct (Inv_fold with "s↦ γs Phys LInv") as "Inv".
      iMod ("Close" with "Inv") as "_". rred2r.

      iMod ((pcs_decr _ _ 96 1) with "Ys") as "[Ys Y]"; [lia|].
      iApply (wpsim_yieldR with "[$Y $Duty]"); [lia|].
      iIntros "Duty _". rred2r.

      iApply (SCMem_load_fun_spec with "[$Mem $h.d↦□] [-]"); [lia|solve_ndisj|].
      iIntros (?) "[%EQ _]". subst. rred2r.

      iApply wpsim_tauR. rred2r.

      iApply "Post". red_tl. iFrame.
    }
    (* Different, CAS fail *)
    iApply (SCMem_cas_loc_fun_spec_gen with "[$Mem $s↦ h.n↦□ h'↦□] [-]"); [lia|solve_ndisj| |].
    { unfold to_val. des_ifs.
      2: iDestruct "h'↦□" as (??) "[h'↦□ _]".
      all: iSplit; try done; iExists _; iFrame "#".
    }
    iClear "h'↦□".
    iIntros (b) "POST". iDestruct "POST" as (u) "(%EQ & s↦ & _ & _)".
    destruct (SCMem.val_eq_dec (to_val h') (to_val h)).
    all: destruct EQ as [-> ->].
    { exfalso. unfold to_val in e. apply NEQhh'.
      destruct h,h'. simpl in *. subst. f_equal. apply proof_irrelevance.
    }

    (* Update ◇[k](0,1) to use for induction *)
    iDestruct (LInv_unfold with "LInv") as "[GMap LivC]".

    iDestruct (ghost_map_lookup with "GMap i↪") as "%Lookup_i".
    iMod (ghost_map_delete with "GMap i↪") as "GMap".

    iDestruct (big_sepM_delete with "LivC") as "[Ob_k LivC]"; [apply Lookup_i|].
    case_decide; [done|].
    red_tl. simpl.

    iDestruct (LInv_fold with "GMap LivC") as "LInv".
    iDestruct (Inv_fold with "s↦ γs Phys LInv") as "Inv".
    iMod ("Close" with "Inv") as "_". rred2r.

    iApply wpsim_tauR. rred2r.

    iApply wpsim_tauR. rred2r.

    (* Do Induction *)
    iMod (pcs_drop _ _ 1 ltac:(auto) 1 101 with "[$PCS]") as "PCS"; [lia|].
    iMod ("IH" with "Ob_k Post Duty PCS AU P Ob_ks") as "IH".
    iApply "IH".
Qed.

End SPEC.

Global Opaque IsT TStack TreiberStack.pop TreiberStack.push.
