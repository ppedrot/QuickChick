Set Implicit Arguments.

Require Import List.
Require Import String.

Require Import RoseTrees.
Require Import Show.
Require Import State.
Require Import AbstractGen.
Require Import Arbitrary.

(* Extraction will map this to something that additionally prints stuff *)
Definition trace (A : Type) (s : string) (a : A) : A := a.

(* Note : Simple Callbacks fall under strict positivity of result... *)
Inductive CallbackKind :=
| Counterexample
| NotCounterexample.

Inductive SmallResult :=
  MkSmallResult : option bool -> bool -> string -> bool ->
                  list (string * nat) -> SmallResult.

Inductive Callback : Type :=
| PostTest :
    CallbackKind -> (State -> SmallResult -> nat) -> Callback
| PostFinalFailure :
    CallbackKind -> (State -> SmallResult -> nat) -> Callback.

Record Result :=
  MkResult {
      ok : option bool;
      expect : bool;
      reason : string;
      interrupted : bool;
      stamp : list (string * nat);
      callbacks : list Callback
    }.

(* I WANT RECORD UPDATES :'( *)
Definition succeeded := MkResult (Some true ) true "" false nil nil.
Definition failed    := MkResult (Some false) true "" false nil nil.
Definition rejected  := MkResult (   None   ) true "" false nil nil.

Definition updReason (r : Result) (s' : string) : Result :=
  match r with
    | MkResult o e _ i s c => MkResult o e s' i s c
  end.

Definition addCallback (res : Result) (c : Callback) : Result :=
  match res with
    | MkResult o e r i s cs => MkResult o e r i s (cons c cs)
  end.

Record QProp : Type := 
  MkProp
    {
      unProp : Rose Result
    }.

Definition Property (Gen: Type -> Type) : Type := Gen QProp.

Section Property.
  Context {Gen : Type -> Type}
          {H: GenMonad Gen}.

  Class Testable (A : Type) : Type :=
    {
      property : A -> Property Gen
    }.

  (* mapping and lifting functions *)

  Definition liftBool (b : bool) : Result :=
    if b then succeeded else updReason failed "Falsifiable".

  Definition mapProp {P : Type} {_ : Testable P}
             (f : QProp -> QProp) (prop : P) : Property Gen :=
    fmapGen f (property prop).

  Definition mapRoseResult {P : Type} {_ : Testable P}
             (f : Rose Result -> Rose Result) (prop : P) : Property Gen :=
    mapProp (fun p => match p with MkProp t => MkProp (f t) end) prop.

  Definition mapTotalResult {prop : Type} {_ : Testable prop}
             (f : Result -> Result) : prop -> Property Gen :=
    mapRoseResult (fmapRose f).

  (* Testable Instances *)
  Global Instance testResult : Testable Result :=
    {|
      (* Left a protectResults out! *)
      property r := returnGen (MkProp (returnRose r))
    |}.
  

  Global Instance testBool : Testable bool :=
    {|
      property b := property (liftBool b)
    |}.
  
  (* ZP/CH: what's the relation between unit and discards? *)
  Global Instance testUnit : Testable unit :=
    {|
      property := fun _ => property rejected
    |}.

  Global Instance testProp : Testable QProp :=
    {|
      property p := returnGen p
    |}.

  Global Instance testGenProp (P : Type) : Testable P -> Testable (Gen P) :=
    {|
      property p := bindGen p property
    |}.

  
  (* Property Combinators *)
  
  (* The following function on its own does not have a decreasing argument...

     Fixpoint props {prop A : Type} {t : Testable prop}
                    (pf : A -> prop) (shrinker : A -> list A) (x : A) :=
       MkRose (property (pf x)) (List.map (props pf shrinker) (shrinker x)).
   *)
  Fixpoint props' {prop A : Type} {t : Testable prop} (n : nat)
           (pf : A -> prop) (shrinker : A -> list A) (x : A) :=
    match n with
      | O =>
        MkRose (property (pf x)) (lazy nil)
      | S n' =>
        MkRose (property (pf x)) (lazy (List.map (props' n' pf shrinker) (shrinker x)))
    end.

  (* Arbitrary choice for number of shrinks.. *)
  Definition props {prop A : Type} `{Testable prop}
             (pf : A -> prop) (shrinker : A -> list A) (x : A) : Rose (Property Gen) :=
    props' 1000 pf shrinker x.

  Definition shrinking {prop A : Type} `{Testable prop}
             (shrinker : A -> list A) (x0 : A) (pf : A -> prop) : Property Gen :=
    @fmapGen Gen _ _ _ (fun x => MkProp (joinRose (fmapRose unProp x)))
             (promote (props pf shrinker x0)).

  Definition callback {prop : Type} `{Testable prop}
             (cb : Callback) : prop -> Property Gen :=
    mapTotalResult (fun r => addCallback r cb).

  Definition printTestCase {prop : Type} `{Testable prop}
             (s : string) (p : prop) : Property Gen :=
    callback (PostFinalFailure Counterexample (fun _st _res => trace s 0)) p.

  Definition whenFail {prop : Type} `{Testable prop}
             (str : string) : prop -> Property Gen :=
    callback (PostFinalFailure Counterexample (fun _st _sr => trace str 0)).


  Definition expectFailure {prop: Type} `{Testable prop} (p: prop) := 
    mapTotalResult (fun res =>
                      MkResult (ok res) false (reason res) 
                             (interrupted res) (stamp res) (callbacks res))
                   p.

  Definition cover {prop : Type} {_ : Testable prop}
             (b : bool) (n : nat) (s : string) : prop -> Property Gen :=
    if b then
      mapTotalResult (fun res =>
                        let '(MkResult o e r i st c) := res in
                        MkResult o e r i ((s,n)::st) c)
    else property.

  Definition classify {prop : Type} {_ : Testable prop}
             (b : bool) (s : string) : prop -> Property Gen :=
    cover b 0 s.

  Definition label {prop : Type} {_ : Testable prop}
             (s : string) : prop -> Property Gen :=
    classify true s.

  Definition collect {A prop : Type} `{_ : Show A} {_ : Testable prop}
             (x : A) : prop -> Property Gen :=
    label (show x).


  Definition implication {prop : Type} `{Testable prop} (b : bool) (p : prop) :=
    if b then property p else property rejected.
       

  Definition forAll {A prop : Type} {_ : Testable prop}
             (show : A -> string) (gen : Gen A)  (pf : A -> prop) : Property Gen :=
    bindGen gen (fun x =>
                   printTestCase (show x ++ newline) (pf x)).

   Definition forAllShrink {A prop : Type} {_ : Testable prop}
             (show : A -> string)
             (gen : Gen A) (shrinker : A -> list A) (pf : A -> prop) : Property Gen :=
    bindGen gen (fun x =>
                   shrinking shrinker x (fun x' =>
                                           printTestCase (show x' ++ newline) (pf x'))).

  Global Instance testFun {A prop : Type} {_ : Show A}
         {_ : Arbitrary A} {_ : Testable prop} : Testable (A -> prop) :=
    {
      property f := forAllShrink show arbitrary shrink f
    }.

  Global Instance testPolyFun {prop : Type -> Type} {_ : Testable (prop nat)} : Testable (forall T, prop T) :=
    {
      property f := printTestCase "" (f nat)
    }.

  Global Instance testPolyFunSet {prop : Set -> Type} {_ : Testable (prop nat)} : Testable (forall T, prop T) :=
    {
      property f := printTestCase "" (f nat)
    }.


End Property.

Notation "x ==> y" := (implication x y) (at level 55, right associativity) 
                      : Property_scope.


 