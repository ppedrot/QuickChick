Require Import QuickCheck.

Class Mutateable (A : Type) : Type :=
{
  mutate : A -> list A
}.

Require Import String. Open Scope string_scope.

Definition force {X} (x : X) := x.

Definition found_bug r :=
  match r with
  | Failure _ _ _ _ _ _ _ _ => true
  | _ => false
  end.

Definition message (kill : bool) (n1 n2 : nat) :=
  (if kill then "Killed" else "Missed") ++
  " mutant " ++ (if kill then "" else "[") ++ show n2
             ++ (if kill then "" else "]")
  ++ " (" ++ show n1 ++ " frags)".

Open Scope nat.
Definition mutateCheckMany {A P : Type} `{_: Testable P}
           `{mutA: Mutateable A} 
           (a : A) (ps : A -> list P) :=
  let mutants := mutate a in
  Property.trace ("Fighting " ++ show (List.length mutants) ++ " mutants")
  (List.fold_left
     (fun n m => match n with (n1,n2) =>
        let kill := List.existsb found_bug (List.map quickCheck (ps m)) in
        let n1' := n1 + (if kill then 1 else 0) in
        let msg := message kill n1' n2 in
        Property.trace msg (n1', n2 + 1)
      end)
     mutants (0, 0)).

Definition mutateCheck {A P: Type} 
           `{_: Testable P} `{mutA: Mutateable A} 
           (a : A) (p : A -> P):=
  mutateCheckMany a (fun a => cons (p a) nil).
