From stdpp Require Import coPset gmap namespaces.
From sflib Require Import sflib.
From Fairness Require Import PCM IProp IPM.
From Fairness Require Import IndexedInvariants LogicSyntaxHOAS.
From iris Require Import bi.big_op.
From iris Require base_logic.lib.invariants.

Local Notation index := nat.

(* Module Base. *)

(*   Section DEF. *)

(*     Variant meta : Type := *)
(*       | src_stateT *)
(*       | tgt_stateT *)
(*       | src_identT *)
(*       | tgt_identT. *)

(*     Inductive t : Type := *)
(*     | unitT *)
(*     | natT *)
(*     | boolT *)
(*     | QpT *)
(*     | coPsetT *)
(*     | gsetTpos *)
(*     | metaT (ty : meta) *)
(*     . *)
(*     (* | gsetT (K : Type) {EqDec : EqDecision K} {Cnt : Countable K}. *) *)

(*   End DEF. *)

(*   Class InterpMeta := *)
(*     { interp : meta -> Type }. *)

(*   Section SEM. *)

(*     Context `{Interp : InterpMeta}. *)

(*     Definition sem (ty : t) : Type := *)
(*       match ty with *)
(*       | unitT => unit *)
(*       | natT => nat *)
(*       | boolT => bool *)
(*       | QpT => Qp *)
(*       | coPsetT => coPset *)
(*       | gsetTpos => gset positive *)
(*       | metaT ty => interp ty *)
(*       end. *)

(*   End SEM. *)

(* End Base. *)

Module Atoms.

  Section ATOMS.

    (* Context `{T : Type}. *)

    (* TODO: more atoms *)

    (* Atoms do not interpret arguments. *)
    Inductive t {Typ : Syntax.type -> Type} : Type :=
    | owne (E : coPset)
    | ownd (D : gset positive)
    | owni (i : positive) (p : @Syntax.t Typ (@t Typ))
    | syn_inv_auth_l (ps : list (prod positive (@Syntax.t Typ (@t Typ))))
    (* Non strictly positive occurrence *)
    (* | own_inv_auth (ps : gmap positive (@Syntax.t Typ (@t Typ))) *)
    .

    (* Inductive t {Typ : @Syntax.type T -> Type} : Type := *)
    (* | owne (E : coPset) *)
    (* | ownd (D : gset positive) *)
    (* | owni (i : positive) (p : @Syntax.t T Typ (@t Typ)) *)
    (* | syn_inv_auth_l (ps : list (prod positive (@Syntax.t T Typ (@t Typ)))) *)
    (* (* Non strictly positive occurrence *) *)
    (* (* | own_inv_auth (ps : gmap positive (@Syntax.t T Typ (@t Typ))) *) *)
    (* . *)

  End ATOMS.

  Section INTERP.

    Context `{Σ : GRA.t}.
    (* Context `{T : Type}. *)
    (* Context `{TSem : T -> Type}. *)

    Local Notation typing := (@Syntax.Typ (@t)).
    Local Notation Formulas := (fun (i : index) => @Syntax.t (typing i) (@t (typing i))).
    (* Local Notation typing := (@Syntax.Typ T TSem (@t T)). *)
    (* Local Notation Formulas := (fun (i : index) => @Syntax.t T (typing i) (@t T (typing i))). *)

    Context `{@GRA.inG (IInvSetRA Formulas) Σ}.
    Context `{@GRA.inG (index ==> CoPset.t)%ra Σ}.
    Context `{@GRA.inG (index ==> Gset.t)%ra Σ}.

    Definition to_semantics (n : index) (a : @t (typing n)) : iProp :=
      match a with
      | owne E => OwnE n E
      | ownd D => OwnD n D
      | owni i p => @OwnI Σ Formulas _ n i p
      | syn_inv_auth_l ps => @inv_auth Σ Formulas _ n (list_to_map ps)
      end.

    (* Definition to_semantics (n : index) (a : @t T (typing n)) : iProp := *)
    (*   match a with *)
    (*   | owne E => OwnE n E *)
    (*   | ownd D => OwnD n D *)
    (*   | owni i p => @OwnI Σ Formulas _ n i p *)
    (*   | syn_inv_auth_l ps => @inv_auth Σ Formulas _ n (list_to_map ps) *)
    (*   end. *)

  End INTERP.

End Atoms.

Section WSAT.

  Context `{Σ : GRA.t}.
  (* Context `{Interp : Base.InterpMeta}. *)

  (* Local Notation T := Base.t. *)
  (* Local Notation TSem := (@Base.sem Base.interp). *)
  (* Local Notation TSem := (Base.sem). *)

  Local Notation typing := (@Syntax.Typ (@Atoms.t)).
  Local Notation Formulas := (fun (n : index) => @Syntax.t (typing n) (@Atoms.t (typing n))).
  (* Local Notation typing := (@Syntax.Typ T TSem (@Atoms.t T)). *)
  (* Local Notation Formulas := (fun (n : index) => @Syntax.t T (typing n) (@Atoms.t T (typing n))). *)

  Context `{@GRA.inG (IInvSetRA Formulas) Σ}.
  Context `{@GRA.inG (index ==> CoPset.t)%ra Σ}.
  Context `{@GRA.inG (index ==> Gset.t)%ra Σ}.

  Local Notation AtomSem := (@Atoms.to_semantics Σ _ _ _).
  Local Notation SynSem := (@Syntax.to_semantics Σ (@Atoms.t) AtomSem).
  (* Local Notation AtomSem := (@Atoms.to_semantics Σ _ TSem _ _ _). *)
  (* Local Notation SynSem := (@Syntax.to_semantics Σ _ TSem (@Atoms.t T) AtomSem). *)

  Global Instance SynIISet : @IInvSet Σ Formulas := (@Syntax.IISet Σ (@Atoms.t) AtomSem).
  (* Global Instance SynIISet : @IInvSet Σ Formulas := (@Syntax.IISet Σ _ TSem (@Atoms.t T) AtomSem). *)


  Definition syn_inv_auth n (ps : gmap positive (Formulas n)) : @Atoms.t (typing n) :=
    Atoms.syn_inv_auth_l (map_to_list ps).
  (* Definition syn_inv_auth n (ps : gmap positive (Formulas n)) : @Atoms.t T (typing n) := *)
  (*   Atoms.syn_inv_auth_l (map_to_list ps). *)

  Lemma syn_inv_auth_iProp
        n ps
    :
    Atoms.to_semantics n (syn_inv_auth n ps) = inv_auth n ps.
  Proof.
    ss. rewrite list_to_map_to_list. ss.
  Qed.

  Import Atoms Syntax.

  Definition syn_inv_satall_fun n : positive -> (Formulas n) -> (Formulas n) :=
    fun i p => or (sepconj p (atom (ownd {[i]}))) (atom (owne {[i]})).
  (* fun i p => Syntax.or (Syntax.sepconj p (Syntax.atom (ownd {[i]}))) (Syntax.atom (owne {[i]})). *)

  Definition syn_inv_satall n (ps : gmap positive (Formulas n)) : Formulas n :=
    @star_gmap (@Atoms.t) n ps (syn_inv_satall_fun n).
    (* @star_gmap _ TSem (@Atoms.t T) n ps (syn_inv_satall_fun n). *)
  (* @Syntax.star_gmap _ TSem (@t T) n ps (inv_satall_fun n). *)


  Lemma syn_inv_satall_fun_iProp
        n i p
    :
    SynSem n (syn_inv_satall_fun n i p) = (((SynSem n p) ∗ (OwnD n {[i]})) ∨ (OwnE n {[i]}))%I.
  Proof.
    unfold syn_inv_satall_fun. rewrite to_semantics_red_or. rewrite to_semantics_red_sepconj. do 2 f_equal.
    all: rewrite to_semantics_red_atom; ss.
  Qed.

  Lemma syn_inv_satall_iProp
        n ps
    :
    SynSem n (syn_inv_satall n ps) = inv_satall n ps.
  Proof.
    ss. unfold syn_inv_satall. rewrite star_gmap_iProp. unfold inv_satall.
    f_equal. extensionalities i p. unfold syn_inv_satall_fun.
    rewrite to_semantics_red_or. rewrite to_semantics_red_sepconj. rewrite ! to_semantics_red_atom.
    ss.
  Qed.

  Definition syn_wsat n : Formulas (S n) :=
    ex (pgmapT formulaT) (fun I => lift (sepconj (atom (syn_inv_auth n I)) (syn_inv_satall n I))).
    (* ex (gmapTpos formulaT) (fun I => lift (sepconj (atom (syn_inv_auth n I)) (syn_inv_satall n I))). *)

  Lemma syn_wsat_iProp
        n
    :
    SynSem (S n) (syn_wsat n) = wsat n.
  Proof.
    unfold syn_wsat, wsat. rewrite to_semantics_red_ex. f_equal. extensionalities I.
    rewrite to_semantics_red_lift. rewrite to_semantics_red_sepconj.
    rewrite to_semantics_red_atom. rewrite syn_inv_auth_iProp. rewrite syn_inv_satall_iProp.
    ss.
  Qed.

End WSAT.

TODO
Section FUPD.

  

End FUPD.


  Context `{Σ : GRA.t}.
  Context `{Vars : index -> Type}.
  Context `{Invs : @IInvSet Σ Vars}.
  (* Context `{Invs : @InvSet Σ (Vars n)}. *)
  Context `{@GRA.inG (index ==> CoPset.t)%ra Σ}.
  Context `{@GRA.inG (index ==> Gset.t)%ra Σ}.
  Context `{@GRA.inG (IInvSetRA Vars) Σ}.

  Variable n : index.

  Local Notation Var := (Vars n).

  Definition inv (N : namespace) P :=
    (∃ p, ∃ i, ⌜prop n p = P⌝ ∧ ⌜i ∈ (↑N : coPset)⌝ ∧ OwnI n i p)%I.

  Definition FUpd (A : iProp) (E1 E2 : coPset) (P : iProp) : iProp :=
    (* A ∗ wsat (prop:=prop n) n ∗ OwnE n E1 -∗ #=> (A ∗ wsat (prop:=prop n) n ∗ OwnE n E2 ∗ P). *)
    A ∗ wsat n ∗ OwnE n E1 -∗ #=> (A ∗ wsat n ∗ OwnE n E2 ∗ P).


  Section INDEXED_INVSET.

    Context `{Σ : GRA.t}.
    Context `{T : Type}.
    Context `{TSem : T -> Type}.

    Local Notation typing := (@Syntax.Typ T TSem (@t T)).
    Local Notation As := (fun (i : index) => @t T (typing i)).
    Local Notation Formulas := (fun (i : index) => @Syntax.t T (typing i) (As i)).

    Context `{@GRA.inG (IInvSetRA Formulas) Σ}.

    Global Instance IISet : @IInvSet Σ As :=
      {| prop := @to_semantics Σ T TSem _ |}.

  End INDEXED_INVSET.

  Section TEST.

    Context `{Σ : GRA.t}.

    Local Notation T := Base.t.
    Local Notation TSem := Base.sem.

    Local Notation typing := (@Syntax.Typ T TSem (@t T)).
    Local Notation Formulas := (fun (i : index) => @Syntax.t T (typing i) (@t T (typing i))).

    Context `{@GRA.inG (IInvSetRA Formulas) Σ}.

    Global Instance testIISet : IInvSet Formulas :=
      @Syntax.IISet Σ T TSem (@t T) IISet.

    Import Base.
    Import Syntax.

    Definition wsat n : Formulas (S n) :=
      ex formulaT (fun p => ex (baseT positiveT) (fun i => sepconj (lift p) (lift (atom (owni n i p))))).

    Lemma wsat_test1 :
      prop 3 (wsat 2) =
        (∃ (p : Formulas 2) (i : positive), (prop 2 p) ∗ (OwnI 2 i p))%I.
    Proof.
      ss.
    Qed.

  End TEST.


  Section TEST.

    Import Syntax.

    Context `{TSem : T -> Type}.

    Local Notation t := Atoms.t.


    Local Notation typing := (@Syntax.Typ T TSem t).
    Local Notation Formulas := (fun (i : index) => @Syntax.t T (typing i) (t (typing i))).

    Definition test1 : Formulas 3 :=
      atom (owni 4 xH (atom (owni 2 xH empty))).

    Definition test_OwnI (n : index) (i : positive) (p : Formulas n) : t (typing n) :=
      @owni (typing n) n i p.

    (* Set Printing All. *)

  End TEST.


  (* Definition inv (N : namespace) P := *)
  (*   (∃ p, ∃ i, ⌜prop n p = P⌝ ∧ ⌜i ∈ (↑N : coPset)⌝ ∧ OwnI n i p)%I. *)

  (* Definition FUpd (A : iProp) (E1 E2 : coPset) (P : iProp) : iProp := *)
  (*   A ∗ wsat n ∗ OwnE n E1 -∗ #=> (A ∗ wsat n ∗ OwnE n E2 ∗ P). *)



(*   Context `{T : Type}. *)
(*     Context `{TSem : T -> Type}. *)

(*     (* Atoms should not interpret arguments. *) *)
(*     Inductive As (V : @type T -> Type) : Type := *)
(*       | owni (p : V formulaT) *)
(*     . *)
(*     (* Inductive As (V : @type T -> Type) : Type := *) *)
(*     (*   | owni (i : index) (p : @t T V (As V)) *) *)
(*     (* . *) *)

(*     Definition typing (i : index) : @type T -> Type := *)
(*       @Typ T TSem As i. *)

(*     (* Definition ttt1 : As (typing 2) := owni (typing 2) 0 (ex formulaT (fun s => pure (s = empty))). *) *)
(*     (* Compute ttt1. *) *)
(*     Definition ttt1 : As (typing 2) := owni (typing 2) (ex formulaT (fun s => pure (s = empty))). *)
(*     Compute ttt1. *)
(*     Goal typing 2 formulaT = @t T (typing 1) (As (typing 1)). *)
(*     Proof. *)
(*       ss. *)
(*     Qed. *)

(*     Definition inv (i : index) (p : typing i formulaT) : *)
(*       @t T (typing i) (As (typing i)) := *)
(*       atom (owni _ p). *)
(*     (* Definition inv (n i : index) (p : @t T (typing i) (As (typing i))) : *) *)
(*     (*   @t T (typing i) (As (typing i)) := *) *)
(*     (*   atom (owni _ n p). *) *)
(*     Definition wsat (i : index) : *)
(*       @t T (typing i) (As (typing i)) := *)
(*       ex formulaT (fun (p : typing i formulaT) => sepconj (lift p) (inv i p)). *)

(*     (* Definition inv0 (n i : index) (p : @t T (typing 2) (As (typing 2))) : *) *)
(*     (*   @t T (typing 3) (As (typing 2)) := *) *)
(*     (*   atom (owni _ n p). *) *)

(*     (* (* Definition of As enforces that  *) *)
(*     (*    p should have the same typing level for itself and its atom  *) *)
(*     (*  *) *) *)
(*     (* Fail Definition inv1 (n : index) (p : @t T (typing 2) (As (typing 3))) : *) *)
(*     (*   @t T (typing 2) (As (typing 3)) := *) *)
(*     (*   atom (owni _ n p). *) *)

(*     (* Definition inv2 q := *) *)
(*     (*   inv 0 3 (atom (owni _ 1 (atom (owni _ 2 q)))). *) *)

(*     (* Fail Definition inv2' q := *) *)
(*     (*   inv 0 3 (atom (owni _ 1 (atom (owni (typing 2) 2 q)))). *) *)

(*     (* Set Printing All. *) *)

(*     (* Definition inv (N : namespace) P := *) *)
(*     (*   (∃ p, ∃ i, ⌜prop p = P⌝ ∧ ⌜i ∈ (↑N : coPset)⌝ ∧ OwnI n i p)%I. *) *)





(*   Section TEST. *)

(*     Context `{A : Type}. *)

(*     Variant tBase := | tBool | tNat. *)
(*     Definition tBase_sem (b : tBase) : Type := *)
(*       match b with | tBool => bool | tNat => nat end. *)

(*     Let Var := @Var tBase tBase_sem A. *)

(*     Compute Var 3 formulaT. *)

(*     (* Goal Var 3 formulaT = @t _ (Var 2) A formulaT. *) *)
(*     Goal Var 3 formulaT = @t _ (Var 2) A. *)
(*     Proof. ss. Qed. *)

(*     Definition syn_bad i := @t tBase (@Var i) A. *)
(*     Notation syn i := (@t tBase (@Var i) A). *)

(*     (* Definition form1 : @syn 2 formulaT := *) *)
(*     Definition form1 : @syn 2 := *)
(*       @ex _ _ _ (baseT tBool) (fun b => empty). *)

(*     (* Goal (syn 1 formulaT) = (Var 2 formulaT). *) *)
(*     Goal (syn 1) = (Var 2 formulaT). *)
(*     Proof. ss. Qed. *)

(*     (* Definition form2 : @syn 2 formulaT := *) *)
(*       (* @ex _ _ _ formulaT (fun (s : Var 2 formulaT) => and (var _ s) (var _ s)). *) *)
(*     Definition form2 : @syn 2 := *)
(*       @ex _ _ _ formulaT (fun (s : Var 2 formulaT) => pure (s = impl empty empty)). *)

(*     (* Definition form3 : @syn 2 formulaT := *) *)
(*     (*   @ex _ _ _ formulaT (fun (s : @t tBase (Var 1) A formulaT) => and (var _ s) (var _ s)). *) *)
(*     Definition form3 : @syn 2 := *)
(*       @ex _ _ _ formulaT (fun (s : @t tBase (Var 1) A) => pure (s = impl empty empty)). *)

(*     (* Definition form4 : @syn 2 formulaT := *) *)
(*     (*   @ex _ _ _ formulaT (fun (s : @syn 1 formulaT) => and (var _ s) (var _ s)). *) *)
(*     Definition form4 : @syn 2 := *)
(*       @ex _ _ _ formulaT (fun (s : @syn 1) => pure (s = impl empty empty)). *)

(*     (* Definition form5 : @syn 2 formulaT := *) *)
(*     (*   @ex _ _ _ formulaT (fun (s : @syn 1 formulaT) => pure (s = wand empty empty)). *) *)
(*     Definition form5 : @syn 2 := *)
(*       @ex _ _ _ formulaT (fun (s : @syn 1) => pure (s = wand empty empty)). *)

(*   End TEST. *)

(* Section TEST. *)

(*     Context `{T : Type}. *)
(*     Context `{TSem : T -> Type}. *)

(*     (* Atoms should not interpret arguments. *) *)
(*     Inductive As (V : @type T -> Type) : Type := *)
(*       | owni (p : V formulaT) *)
(*     . *)
(*     (* Inductive As (V : @type T -> Type) : Type := *) *)
(*     (*   | owni (i : index) (p : @t T V (As V)) *) *)
(*     (* . *) *)

(*     Definition typing (i : index) : @type T -> Type := *)
(*       @Typ T TSem As i. *)

(*     (* Definition ttt1 : As (typing 2) := owni (typing 2) 0 (ex formulaT (fun s => pure (s = empty))). *) *)
(*     (* Compute ttt1. *) *)
(*     Definition ttt1 : As (typing 2) := owni (typing 2) (ex formulaT (fun s => pure (s = empty))). *)
(*     Compute ttt1. *)
(*     Goal typing 2 formulaT = @t T (typing 1) (As (typing 1)). *)
(*     Proof. *)
(*       ss. *)
(*     Qed. *)

(*     Definition inv (i : index) (p : typing i formulaT) : *)
(*       @t T (typing i) (As (typing i)) := *)
(*       atom (owni _ p). *)
(*     (* Definition inv (n i : index) (p : @t T (typing i) (As (typing i))) : *) *)
(*     (*   @t T (typing i) (As (typing i)) := *) *)
(*     (*   atom (owni _ n p). *) *)
(*     Definition wsat (i : index) : *)
(*       @t T (typing i) (As (typing i)) := *)
(*       ex formulaT (fun (p : typing i formulaT) => sepconj (lift p) (inv i p)). *)

(*     (* Definition inv0 (n i : index) (p : @t T (typing 2) (As (typing 2))) : *) *)
(*     (*   @t T (typing 3) (As (typing 2)) := *) *)
(*     (*   atom (owni _ n p). *) *)

(*     (* (* Definition of As enforces that  *) *)
(*     (*    p should have the same typing level for itself and its atom  *) *)
(*     (*  *) *) *)
(*     (* Fail Definition inv1 (n : index) (p : @t T (typing 2) (As (typing 3))) : *) *)
(*     (*   @t T (typing 2) (As (typing 3)) := *) *)
(*     (*   atom (owni _ n p). *) *)

(*     (* Definition inv2 q := *) *)
(*     (*   inv 0 3 (atom (owni _ 1 (atom (owni _ 2 q)))). *) *)

(*     (* Fail Definition inv2' q := *) *)
(*     (*   inv 0 3 (atom (owni _ 1 (atom (owni (typing 2) 2 q)))). *) *)

(*     (* Set Printing All. *) *)

(*     (* Definition inv (N : namespace) P := *) *)
(*     (*   (∃ p, ∃ i, ⌜prop p = P⌝ ∧ ⌜i ∈ (↑N : coPset)⌝ ∧ OwnI n i p)%I. *) *)

(* End TEST. *)
