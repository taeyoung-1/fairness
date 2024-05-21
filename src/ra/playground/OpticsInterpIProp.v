From sflib Require Import sflib.
From Paco Require Import paco.
From Fairness Require Import Optics IProp IPM PCM.
From stdpp Require Import coPset gmap namespaces.
From Fairness Require Export IndexedInvariants.

Set Implicit Arguments.

Require Import Program.

Section STATE.

  Context `{Σ: GRA.t}.

  Class ViewInterp {S V} (l : Lens.t S V) (SI : S -> iProp) (VI : V -> iProp) := {
      view_interp : forall s, (SI s) ⊢ (VI (Lens.view l s) ∗ ∀ x, VI x -∗ SI (Lens.set l x s))
    }.

  Definition interp_prod {A B} (SA: A -> iProp) (SB: B -> iProp):
    (A * B -> iProp) :=
    fun '(sa, sb) => (SA sa ∗ SB sb)%I.

  Global Program Instance ViewInterp_fstl {A B}
         (SA: A -> iProp) (SB: B -> iProp)
    : ViewInterp fstl (interp_prod SA SB) SA.
  Next Obligation.
  Proof.
    iIntros "[H0 H1]". iSplitL "H0".
    { iExact "H0". }
    { iIntros (?) "H0". iFrame. }
  Qed.

  Global Program Instance ViewInterp_sndl {A B}
         (SA: A -> iProp) (SB: B -> iProp)
    : ViewInterp sndl (interp_prod SA SB) SB.
  Next Obligation.
  Proof.
    iIntros "[H0 H1]". iSplitL "H1".
    { iExact "H1". }
    { iIntros (?) "H1". iFrame. }
  Qed.

  Global Program Instance ViewInterp_id {S} (SI: S -> iProp): ViewInterp Lens.id SI SI.
  Next Obligation.
  Proof.
    iIntros "H". iSplitL "H".
    { iExact "H". }
    { iIntros (?) "H". iExact "H". }
  Qed.

  Global Program Instance ViewInterp_compose {A B C}
         {lab: Lens.t A B}
         {lbc: Lens.t B C}
         (SA: A -> iProp) (SB: B -> iProp) (SC: C -> iProp)
         `{VAB: ViewInterp _ _ lab SA SB}
         `{VBC: ViewInterp _ _ lbc SB SC}
    :
    ViewInterp (Lens.compose lab lbc) SA SC.
  Next Obligation.
  Proof.
    iIntros "H".
    iPoseProof (view_interp with "H") as "[H K0]".
    iPoseProof (view_interp with "H") as "[H K1]".
    iSplitL "H"; [auto|]. iIntros (?) "H".
    iApply "K0". iApply "K1". iApply "H".
  Qed.

  Definition N_state_src := (nroot .@ "_state_src").
  Definition E_state_src: coPset := ↑ N_state_src.
  Definition N_state_tgt := (nroot .@ "_state_tgt").
  Definition E_state_tgt: coPset := ↑ N_state_tgt.

  Variable state_src: Type.
  Variable state_tgt: Type.

  Local Notation stateSrcRA := (Auth.t (Excl.t (option state_src)) : URA.t).
  Local Notation stateTgtRA := (Auth.t (Excl.t (option state_tgt)) : URA.t).

  Local Notation index := nat.
  Context `{Vars : index -> Type}.
  Context `{Invs : @IInvSet Σ Vars}.

  Context `{STATESRC: @GRA.inG (stateSrcRA) Σ}.
  Context `{STATETGT: @GRA.inG (stateTgtRA) Σ}.
  Context `{COPSETRA : @PCM.GRA.inG (PCM.URA.pointwise index PCM.CoPset.t) Σ}.
  Context `{GSETRA : @PCM.GRA.inG (PCM.URA.pointwise index PCM.Gset.t) Σ}.
  Context `{INVSETRA : @GRA.inG (IInvSetRA Vars) Σ}.

  Definition St_src (st_src: state_src): iProp :=
    OwnM (Auth.white (Excl.just (Some st_src): @Excl.t (option state_src)): stateSrcRA).

  Definition Vw_src (st: state_src) {V} (l : Lens.t state_src V) (v : V) : iProp :=
    St_src (Lens.set l v st).

  Definition src_interp_as n {V} (l: Lens.t state_src V) (VI: V -> iProp) :=
    (∃ SI (p : Vars n),
        (⌜prop _ p = (∃ st, St_src st ∗ SI st)%I⌝)
          ∗ (inv n N_state_src p) ∗ ⌜ViewInterp l SI VI⌝)%I.

  Global Program Instance src_interp_as_persistent n {V} (l: Lens.t state_src V) (VI: V -> iProp): Persistent (src_interp_as n l VI).

  Definition mask_has_st_src (Es : coPsets) n := (match Es !! n with Some E => (↑N_state_src) ⊆ E | None => True end).

  Global Program Instance src_interp_as_acc x A Es n {V} (l: Lens.t state_src V) (VI: V -> iProp):
    IntoAcc
      (src_interp_as n l VI)
      (n < x /\ mask_has_st_src Es n) True
      (FUpd x A Es (<[n := (Es !? n) ∖ E_state_src]>Es))
      (FUpd x A (<[n := (Es !? n) ∖ E_state_src]>Es) Es)
      (fun (st: state_src) => ∃ vw, Vw_src st l vw ∗ VI vw)%I
      (fun (st: state_src) => ∃ vw, Vw_src st l vw ∗ VI vw)%I
      (fun _ => None).
  Next Obligation.
  Proof.
    iIntros "[% [% [%PIS [INV %]]]] _".
    iInv "INV" as "INTERP" "K".
    rewrite ! PIS. iDestruct "INTERP" as "[% [ST INTERP]]".
    iModIntro. iPoseProof (view_interp with "INTERP") as "[INTERP SET]".
    iExists _. iSplitL "ST INTERP".
    { iExists _. iFrame. unfold Vw_src. iEval (rewrite Lens.set_view). iFrame. }
    iIntros "[% [ST INTERP]]".
    iPoseProof ("SET" with "INTERP") as "INTERP".
    iApply ("K" with "[ST INTERP]"). iExists _. iFrame.
  Qed.

  Lemma src_interp_as_id x A Es n (LT: n < x) (SI: state_src -> iProp)
        p (IN : prop n p = (∃ st, St_src st ∗ SI st)%I):
    (∃ st, St_src st ∗ SI st) ⊢ FUpd x A Es Es (src_interp_as n Lens.id SI).
  Proof.
    iIntros "H". rewrite <- IN. iMod (FUpd_alloc with "H") as "H". auto.
    iModIntro. iExists _, p. iSplit. auto. iSplit. auto.
    iPureIntro. typeclasses eauto.
  Qed.

  Lemma src_interp_as_compose n A B
        {la: Lens.t state_src A}
        {lb: Lens.t A B}
        (SA: A -> iProp)
        (SB: B -> iProp)
        `{VAB: ViewInterp _ _ lb SA SB}
    :
    src_interp_as n la SA ⊢ src_interp_as n (Lens.compose la lb) SB.
  Proof.
    iIntros "[% [% [% [H %]]]]". iExists _, p. iSplit; [eauto|]. iSplit; [eauto|].
    iPureIntro. typeclasses eauto.
  Qed.



  Definition St_tgt (st_tgt: state_tgt): iProp :=
    OwnM (Auth.white (Excl.just (Some st_tgt): @Excl.t (option state_tgt)): stateTgtRA).

  Definition Vw_tgt (st: state_tgt) {V} (l : Lens.t state_tgt V) (v : V) : iProp :=
    St_tgt (Lens.set l v st).

  Definition tgt_interp_as n {V} (l: Lens.t state_tgt V) (VI: V -> iProp) :=
    (∃ SI (p : Vars n),
        (⌜prop _ p = (∃ st, St_tgt st ∗ SI st)%I⌝)
          ∗ (inv n N_state_tgt p) ∗ ⌜ViewInterp l SI VI⌝)%I.

  Global Program Instance tgt_interp_as_persistent n {V} (l: Lens.t state_tgt V) (VI: V -> iProp): Persistent (tgt_interp_as n l VI).

  Definition mask_has_st_tgt (Es : coPsets) n := (match Es !! n with Some E => (↑N_state_tgt) ⊆ E | None => True end).

  Global Program Instance tgt_interp_as_acc x A Es n {V} (l: Lens.t state_tgt V) (VI: V -> iProp):
    IntoAcc
      (tgt_interp_as n l VI)
      (n < x /\ mask_has_st_tgt Es n) True
      (FUpd x A Es (<[n:=(Es !? n) ∖ E_state_tgt]>Es))
      (FUpd x A (<[n:=(Es !? n) ∖ E_state_tgt]>Es) Es)
      (fun (st: state_tgt) => ∃ vw, Vw_tgt st l vw ∗ VI vw)%I
      (fun (st: state_tgt) => ∃ vw, Vw_tgt st l vw ∗ VI vw)%I
      (fun _ => None).
  Next Obligation.
  Proof.
    iIntros "[% [% [%PIS [INV %]]]] _".
    iInv "INV" as "INTERP" "K".
    rewrite ! PIS. iDestruct "INTERP" as "[% [ST INTERP]]".
    iModIntro. iPoseProof (view_interp with "INTERP") as "[INTERP SET]".
    iExists _. iSplitL "ST INTERP".
    { iExists _. iFrame. unfold Vw_tgt. iEval (rewrite Lens.set_view). iFrame. }
    iIntros "[% [ST INTERP]]".
    iPoseProof ("SET" with "INTERP") as "INTERP".
    iApply ("K" with "[ST INTERP]"). iExists _. iFrame.
  Qed.

  Lemma tgt_interp_as_id x A Es n (LT: n < x) (SI: state_tgt -> iProp)
        p (IN : prop n p = (∃ st, St_tgt st ∗ SI st)%I):
    (∃ st, St_tgt st ∗ SI st) ⊢ FUpd x A Es Es (tgt_interp_as n Lens.id (SI)).
  Proof.
    iIntros "H". rewrite <- IN. iMod (FUpd_alloc with "H") as "H". auto.
    iModIntro. iExists _, p. iSplit. auto. iSplit. auto.
    iPureIntro. typeclasses eauto.
  Qed.

  Lemma tgt_interp_as_compose n A B
        {la: Lens.t state_tgt A}
        {lb: Lens.t A B}
        (SA: A -> iProp)
        (SB: B -> iProp)
        `{VAB: ViewInterp _ _ lb SA SB}
    :
    tgt_interp_as n la SA ⊢ tgt_interp_as n (Lens.compose la lb) SB.
  Proof.
    iIntros "[% [% [% [H %]]]]". iExists _, p. iSplit; [eauto|]. iSplit; [eauto|].
    iPureIntro. typeclasses eauto.
  Qed.

End STATE.
