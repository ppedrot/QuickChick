Require Import Datatypes.
Require Import Lattices.
Require Import ZArith.
Require Import List.
Require Import EquivDec.
Require Import String.
Require Import Show.

Fixpoint replicate {A:Type} (n:nat) (a:A) : list A :=
  match n with
    | O => nil
    | S n' => a :: replicate n' a
  end.

Definition zreplicate {A:Type} (n:Z) (a:A) : option (list A) :=
  if Z_lt_dec n 0 then None
  else Some (replicate (Z.to_nat n) a).

Lemma index_list_replicate: forall A n (a:A) n',
  index_list n' (replicate n a) = if lt_dec n' n then Some a else None.
Proof.
  induction n; destruct n'; simpl; try congruence.
  rewrite IHn.
  do 2 destruct lt_dec; try congruence; try omega.
Qed.

Lemma index_list_Z_zreplicate: forall A z (a:A) z' l,
  zreplicate z a = Some l ->
  index_list_Z z' l = if Z_le_dec 0 z' then
                        if Z_lt_dec z' z then Some a else None else None.
Proof.
  unfold zreplicate, index_list_Z; intros.
  destruct (Z_lt_dec z 0); try congruence.
  inv H.
  destruct (z' <? 0)%Z eqn:Ez.
  - rewrite Z.ltb_lt in Ez.
    destruct Z_lt_dec; try omega.
    destruct Z_le_dec; auto; omega.
  - assert (~ (z' < 0 )%Z).
    rewrite <- Z.ltb_lt; try congruence.
    destruct Z_le_dec; try omega.
    rewrite index_list_replicate.
    assert ( (z'<z)%Z <-> (Z.to_nat z') < (Z.to_nat z)).
      apply Z2Nat.inj_lt; try omega.
    destruct lt_dec; destruct Z_lt_dec; auto; try omega.
Qed.

Inductive alloc_mode := Global | Local.

(* Frames are parameterized over the type of block and the type of Label *)
(* Cannot make this a parameter because we don't want it opaque. 
   Keep it outside for now, until I figure out what's better *)
(* Any better solutions than the implicit arguments welcome *)
Inductive frame {A S} := Fr (stamp : S) (label : S) : list A -> @frame A S.

(* Labels have to have an "everything below it" function for generation/indist *)
Class AllThingsBelow (S: Type):=
{
  allThingsBelow : S -> list S
}.

Module Type MEM.
  (* Type of memory is parameterized by the type of stamps and the type of block *)
  Parameter t : Type -> Type -> Type.

  Parameter block : Type -> Type.
  Declare Instance EqDec_block : forall {S} {_:EqDec S eq}, EqDec (block S) eq.
  Parameter stamp : forall {S}, block S -> S.

  (* For generation *)
  Parameter put_stamp : forall {S}, S -> block S -> block S.
  (* For indistinguishability - return all frames with stamps 
     less than a label (called with top) *)
  Parameter get_all_blocks : forall {A S} {_: AllThingsBelow S}, S -> t A S -> list (block S).
  (* For printing *)
  Declare Instance show_block : forall {S} {_: Show S}, Show (block S).

  (* DD -> DP : is a block some kind of "stamped pointer"? *)
  Parameter get_frame : forall {A S}, t A S -> block S -> option (@frame A S).
  Parameter upd_frame : 
    forall {A S:Type} {EqS:EqDec S eq}, t A S -> block S -> @frame A S ->
                                        option (t A S).
  Parameter upd_get_frame : forall A S (EqS:EqDec S eq) (m:t A S) (b:block S) fr fr',
    get_frame m b = Some fr ->
    exists m',
      upd_frame m b fr' = Some m'.
  Parameter get_upd_ : forall A S (EqS:EqDec S eq) (m m':t A S) (b:block S) fr,
    upd_frame m b fr = Some m' ->
    forall b', 
      get_frame m' b' = if b == b' then Some fr else get_frame m b'.
  Parameter upd_frame_defined : forall A S (EqS:EqDec S eq) (m m':t A S) (b:block S) fr,
    upd_frame m b fr = Some m' ->
    exists fr', get_frame m b = Some fr'.

  Parameter empty : forall A S, t A S.
  Parameter get_empty : forall A S (b:block S), get_frame (empty A S) b = None.

  (* Create a memory with some block initialized to a frame *)
  Parameter init : forall A S {eqS:EqDec S eq},
                     alloc_mode ->
                     block S ->
                     @frame A S ->
                     t A S.

  Parameter get_init_eq : forall A S {eqS:EqDec S eq}
                                 mode (b : block S) (f : @frame A S),
                            get_frame (init A S mode b f) b = Some f.

  Parameter get_init_neq : forall A S {eqS:EqDec S eq}
                                  mode (b b' : block S) (f : @frame A S),
                             b' <> b ->
                             get_frame (init A S mode b f) b' = None.

  Parameter alloc :
    forall {A S} {EqS:EqDec S eq}, alloc_mode -> t A S -> S -> @frame A S -> (block S * t A S).
  Parameter alloc_stamp : forall A S (EqS:EqDec S eq) am (m m':t A S) s fr b, 
    alloc am m s fr = (b,m') -> stamp b = s.
  Parameter alloc_get_fresh : forall A S (EqS:EqDec S eq) am (m m':t A S) s fr b, 
    alloc am m s fr = (b,m') -> get_frame m b = None.
  Parameter alloc_get_frame : forall A S (eqS:EqDec S eq) am (m m':t A S) s fr b, 
    alloc am m s fr = (b,m') ->
    forall b', get_frame m' b' = if b == b' then Some fr else get_frame m b'.
  Parameter alloc_upd : forall A S (eqS:EqDec S eq) am (m:t A S) b fr1 s fr2 m',
    upd_frame m b fr1 = Some m' ->
    fst (alloc am m' s fr2) = fst (alloc am m s fr2).
  Parameter alloc_local_comm : 
    forall A S (EqS:EqDec S eq)  (m m1 m2 m1' m2':t A S) s s' fr fr' b1 b2 b1', 
    s <> s' ->                                           
    alloc Local m s fr = (b1,m1) -> 
    alloc Local m1 s' fr' = (b2,m2) -> 
    alloc Local m s' fr' = (b1',m1') ->
    b1' = b2.
  Parameter alloc2_local : 
    forall A S (EqS:EqDec S eq)  (m1 m2 m1' m2':t A S) s fr1 fr2 fr' b, 
    alloc Local m1 s fr1 = (b,m1') -> 
    alloc Local m2 s fr2 = (b,m2') ->
    fst (alloc Local m1' s fr') = fst (alloc Local m2' s fr').

  Parameter alloc_next_block_no_fr : 
    forall A S (EqS:EqDec S eq) (m:t A S) s fr1 fr2,
    fst (alloc Local m s fr1) = fst (alloc Local m s fr2).

  Parameter map : forall {A B S}, (@frame A S -> @frame B S) -> t A S -> t B S.
  Parameter map_spec : forall A B S (f: @frame A S -> @frame B S) (m:t A S),
    forall b, get_frame (map f m) b = option_map f (get_frame m b).

End MEM.

(* For indist/generation purposes, our implementation has to be less generic or
   give our labels a function "allLabelsBelow". For now do the latter *)
Module Mem: MEM.
  Definition block S := (Z * S)%type.

  Instance EqDec_block : forall {S} {EqS:EqDec S eq}, EqDec (block S) eq.
  Proof.
    intros S E (x,s) (x',s').
    destruct (Z.eq_dec x x').
    destruct (s == s').
    left; congruence.
    right; congruence.
    right; congruence.
  Qed.

  Definition stamp S : block S -> S := snd.
  Definition put_stamp S (s : S) (b : block S) : block S :=
    let (z,_) := b in (z,s).

  Record _t {A S} := MEM {
     content :> block S -> option (@frame A S);
     next : S -> Z;
     content_next : forall s i, (next s<=i)%Z -> content (i,s) = None
  }.
  Implicit Arguments _t [].
  Implicit Arguments MEM [A S].
  Definition t := _t.

  Definition get_frame {A S} (m:t A S) := content m.

  Definition Z_seq z1 z2 := map Z.of_nat (seq (Z.to_nat z1) (Z.to_nat z2)).

  Fixpoint list_of_option {A : Type} (l : list (option A)) : list A :=
    match l with
      | nil => nil
      | Some h :: t => h :: list_of_option t
      | None :: t => list_of_option t
    end.

  Definition get_blocks_at_level {A S} (m : t A S) (s : S):=
    let max := next m s in
    let indices := Z_seq 1%Z (max - 1) in
    map (fun ind => (ind,s)) indices.

  Definition get_all_blocks {A S} {_: AllThingsBelow S} (s : S) (m : t A S) 
: list (block S) :=
    flat_map (get_blocks_at_level m) (allThingsBelow s).

  Instance show_block {S} {_: Show S}: Show (block S) :=
  {|
    show b :=
      let (z,s) := b in
      ("(" ++ show z ++ " @ " ++ show s ++ ")")%string
  |}.

  Program Definition map {A B S} (f:@frame A S -> @frame B S) (m:t A S) : t B S:= 
    MEM 
      (fun b => option_map f (get_frame m b))
      (next m)
      _.
  Next Obligation.
    simpl; rewrite content_next; auto.
  Qed.

  Lemma map_spec : forall A B S (f:@frame A S -> @frame B S) (m:t A S),
    forall b, get_frame (map f m) b = option_map f (get_frame m b).
  Proof.
    auto.
  Qed.

  Program Definition empty A S : t A S := MEM 
    (fun b => None) (fun _ => 1%Z) _.

  Lemma get_empty : forall A S b, get_frame (empty A S)  b = None.
  Proof. auto. Qed.

  Program Definition init A S {eqS : EqDec S eq} (am : alloc_mode) b f : t A S:= MEM
    (fun b' : block S => if b' == b then Some f else None)
    (fun s => if s == stamp _ b then fst b + 1 else 1)%Z
    _.
  Next Obligation.
    simpl in *.
    destruct (s == s0) as [EQ | NEQ].
    - compute in EQ. subst s0.
      destruct (equiv_dec (i,s)) as [contra|]; trivial.
      inv contra.
      omega.
    - destruct (equiv_dec (i,s)) as [E|E]; try congruence.
  Qed.

  Lemma get_init_eq : forall A S {eqS:EqDec S eq}
                             mode (b : block S) (f : @frame A S),
                        get_frame (init A S mode b f) b = Some f.
  Proof.
    unfold init. simpl.
    intros.
    match goal with
      | |- context [if ?b then _ else _] =>
        destruct b; congruence
    end.
  Qed.

  Lemma get_init_neq : forall A S {eqS:EqDec S eq}
                              mode (b b' : block S) (f : @frame A S),
                         b' <> b ->
                         get_frame (init A S mode b f) b' = None.
  Proof.
    unfold init. simpl.
    intros.
    match goal with
      | |- context [if ?b then _ else _] =>
        destruct b; congruence
    end.
  Qed.

  Program Definition upd_frame_rich {A S} {EqS:EqDec S eq} (m:t A S) (b0:block S) (fr:@frame A S)
  : option { m' : (t A S) |
             (forall b', 
                get_frame m' b' = if b0 == b' then Some fr else get_frame m b') 
           /\ forall s, next m s = next m' s} :=
    match m b0 with
      | None => None
      | Some _ =>
        Some (MEM
                (fun b => if b0 == b then Some fr else m b) 
                (next m) _)
    end.
  Next Obligation.
    destruct (equiv_dec b0).
    - destruct b0; inv e.
      rewrite content_next in Heq_anonymous; congruence.
    - apply content_next; auto.
  Qed.

  Definition upd_frame {A S} {EqS:EqDec S eq} (m:t A S) (b0:block S) (fr:@frame A S)
  : option (t A S) := 
    match upd_frame_rich m b0 fr with
      | None => None
      | Some (exist m' _) => Some m'
    end.

  Lemma upd_get_frame : forall A S (EqS:EqDec S eq) (m:t A S) (b:block S) fr fr',
    get_frame m b = Some fr ->
    exists m',
      upd_frame m b fr' = Some m'.
  Proof.
    (* Sad.... *)
    unfold upd_frame, upd_frame_rich, get_frame.
    intros.
    generalize (@eq_refl (option (@frame A S)) (m b)).
    generalize (upd_frame_rich_obligation_2 A S EqS m b fr').
    simpl.
    generalize (upd_frame_rich_obligation_1 A S EqS m b fr').
    rewrite H.
    simpl.
    intros H1 H2 H3.
    eauto.
  Qed.

  Lemma get_upd_frame : forall A S (eqS:EqDec S eq) (m m':t A S) (b:block S) fr,
    upd_frame m b fr = Some m' ->
    forall b', 
      get_frame m' b' = if b == b' then Some fr else get_frame m b'.
  Proof.
    unfold upd_frame; intros.
    destruct (upd_frame_rich m b fr); try congruence.
    destruct s; inv H; intuition.    
  Qed.

  Lemma upd_frame_defined : forall A S (EqS:EqDec S eq) (m m':t A S) (b:block S) fr,
    upd_frame m b fr = Some m' ->
    exists fr', get_frame m b = Some fr'.
  Proof.
    unfold upd_frame, upd_frame_rich, get_frame.
    intros until 0.
    generalize (@eq_refl (option (@frame A S)) (@content A S m b)).
    generalize (upd_frame_rich_obligation_2 A S EqS m b fr).
    simpl.
    generalize (upd_frame_rich_obligation_1 A S EqS m b fr).
    simpl.
    intros.
    destruct (m b); eauto; congruence.
  Qed.

  Opaque Z.add.

  Program Definition alloc
             {A S} {EqS:EqDec S eq} (am:alloc_mode) (m:t A S) (s:S) (fr:@frame A S) 
            : (block S * t A S) :=
    ((next m s,s),
     MEM
       (fun b' => if (next m s,s) == b' then Some fr else get_frame m b')
       (fun s' => if s == s' then (1 + next m s)%Z else next m s')
       _).
  Next Obligation.
    destruct (equiv_dec (next m s, s)).
    - inv e.
      destruct (equiv_dec s0); try congruence.
      omega.
    - destruct (equiv_dec s).
      + inv e.
        apply content_next; omega.
      + apply content_next; omega.
  Qed.

  Lemma alloc_stamp : forall A S (EqS:EqDec S eq) am (m m':t A S) s fr b, 
    alloc am m s fr = (b,m') -> stamp _ b = s.
  Proof.
    unfold alloc; intros.
    inv H; auto.
  Qed.

  Lemma alloc_get_fresh : forall A S (EqS:EqDec S eq) am (m m':t A S) s fr b, 
    alloc am m s fr = (b,m') -> get_frame m b = None.
  Proof.
    unfold alloc; intros.
    inv H.
    apply content_next; omega.
  Qed.

  Lemma alloc_get_frame : forall A S (eqS:EqDec S eq) am (m m':t A S) s fr b, 
    alloc am m s fr = (b,m') ->
    forall b', get_frame m' b' = if b == b' then Some fr else get_frame m b'.
  Proof.
    unfold alloc; intros.
    inv H; auto.
  Qed.

  Lemma alloc_upd : forall A S (eqS:EqDec S eq) am (m:t A S) b fr1 s fr2 m',
    upd_frame m b fr1 = Some m' ->
    fst (alloc am m' s fr2) = fst (alloc am m s fr2).
  Proof.
    intros A S eqS am m b fr1 s fr2 m' H.
    unfold alloc, upd_frame in *; simpl.
    destruct (upd_frame_rich m b fr1); try congruence.
    destruct s0; inv H.
    destruct a as [_ T].
    rewrite T; auto.
  Qed.

  Lemma alloc_local_comm : 
    forall A S (EqS:EqDec S eq) (m m1 m2 m1' m2':t A S) s s' fr fr' b1 b2 b1', 
    s <> s' ->                                           
    alloc Local m s fr = (b1,m1) -> 
    alloc Local m1 s' fr' = (b2,m2) -> 
    alloc Local m s' fr' = (b1',m1') ->
    b1' = b2.
  Proof.
    intros A S EqS m m1 m2 m1' m2' s s' fr fr' b1 b2 b1' H H0 H1 H2.
    inv H0; inv H1; inv H2.
    destruct (equiv_dec s s'); try congruence.
  Qed.

  Lemma alloc2_local : 
    forall A S (EqS:EqDec S eq)  (m1 m2 m1' m2':t A S) s fr1 fr2 fr' b, 
    alloc Local m1 s fr1 = (b,m1') -> 
    alloc Local m2 s fr2 = (b,m2') ->
    fst (alloc Local m1' s fr') = fst (alloc Local m2' s fr').
  Proof.
    intros A S EqS m1 m2 m1' m2' s fr1 fr2 fr' b H H0.
    inv H; inv H0; simpl.
    rewrite H1; auto.
  Qed.

  Lemma alloc_next_block_no_fr : 
    forall A S (EqS:EqDec S eq) (m:t A S) s fr1 fr2,
    fst (alloc Local m s fr1) = fst (alloc Local m s fr2).
  Proof.
    intros A S EqS m s fr1 fr2.
    unfold alloc; simpl; auto.
  Qed.

End Mem.
