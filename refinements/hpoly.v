(** This file is part of CoqEAL, the Coq Effective Algebra Library.
(c) Copyright INRIA and University of Gothenburg, see LICENSE *)
From mathcomp Require Import ssreflect ssrfun ssrbool eqtype ssrnat div seq zmodp.
From mathcomp Require Import path choice fintype tuple finset ssralg bigop poly.

From CoqEAL Require Import param refinements pos hrel.

(******************************************************************************)
(** This file implements sparse polynomials in sparse Horner normal form.     *)
(*                                                                            *)
(******************************************************************************)

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Local Open Scope ring_scope.

Import GRing.Theory Refinements.Op.

(******************************************************************************)
(** PART I: Defining generic datastructures and programming with them         *)
(******************************************************************************)
Section hpoly.

Context {A N pos : Type}.

Inductive hpoly A := Pc : A -> hpoly A
                   | PX : A -> pos -> hpoly A -> hpoly A.

Section hpoly_op.

Context `{zero_of A, one_of A, add_of A, sub_of A, opp_of A, mul_of A, eq_of A}.
Context `{one_of pos, add_of pos, sub_of pos, eq_of pos, leq_of pos(*, lt_of pos*)}.
Context `{zero_of N, one_of N, eq_of N, leq_of N(*, lt_of N*), add_of N, sub_of N}.
Context `{cast_of N pos, cast_of pos N}.

Local Open Scope computable_scope.

Fixpoint normalize (p : hpoly A) : hpoly A := match p with
  | Pc c => Pc c
  | PX a n p => match normalize p with
    | Pc c => PX a n (Pc c)
    | PX b m q => if (b == 0)%C then PX a (m + n) q else PX a n (PX b m q)
    end
  end.

Fixpoint from_seq (p : seq A) : hpoly A := match p with
  | [::] => Pc 0
  | [:: c] => Pc c
  | x :: xs => PX x 1 (from_seq xs)
  end.

Global Instance cast_hpoly : cast_of A (hpoly A) := fun x => Pc x.

Global Instance zero_hpoly : zero_of (hpoly A) := Pc 0.
Global Instance one_hpoly  : one_of (hpoly A)  := Pc 1.

Fixpoint map_hpoly A B (f : A -> B) (p : hpoly A) : hpoly B := match p with
  | Pc c     => Pc (f c)
  | PX a n p => PX (f a) n (map_hpoly f p)
  end.

Global Instance opp_hpoly : opp_of (hpoly A) := map_hpoly -%C.
Global Instance scale_hpoly : scale_of A (hpoly A) :=
  fun a => map_hpoly [eta *%C a].

Fixpoint addXn_const (n : N) a (q : hpoly A) := match q with
  | Pc b      => if (n == 0)%C then Pc (a + b) else PX b (cast n) (Pc a)
  | PX b m q' => let cn := cast n in
    if (n == 0)%C then PX (a + b) m q' else
      if (n == cast m)%C    then PX b m (addXn_const 0 a q') else
        if (*n < cast m*) (n <= cast m)%C && ~~(n == cast m)%C
        then PX b cn (PX a (m - cn) q')
                    else PX b m (addXn_const (n - cast m)%C a q')
  end.

Fixpoint addXn (n : N) p q {struct p} := match p, q with
  | Pc a      , q      => addXn_const n a q
  | PX a n' p', Pc b   => if (n == 0)%C then PX (a + b) n' p'
                                        else PX b (cast n) (PX a n' p')
  | PX a n' p', PX b m q' =>
    if (n == 0)%C then
      if (n' == m)%C then PX (a + b) n' (addXn 0 p' q') else
        if (*n' < m*) (n' <= m)%C && ~~(n' == m)%C
        then PX (a + b) n' (addXn 0 p' (PX 0 (m - n') q'))
        else PX (a + b) m (addXn (cast (n' - m)) p' q')
    else addXn (n + cast n') p' (addXn_const 0 b (addXn_const n a (PX 0 m q')))
  end.

(* (* This definition is nicer but Coq doesn't like it *) *)
(* Fixpoint add_hpoly_op p q := match p, q with *)
(*   | Pc a, Pc b     => Pc (a + b) *)
(*   | PX a n p, Pc b => PX (a + b) n p *)
(*   | Pc a, PX b n p => PX (a + b) n p *)
(*   | PX a n p, PX b m q => *)
(*   if (m == n)%C then PX (a + b) n (add_hpoly_op p q) *)
(*                 else if n < m then PX (a + b) n (add_hpoly_op p (PX 0 (m - n) q)) *)
(*                               else PX (a + b) m (add_hpoly_op q (PX 0 (n - m) p)) *)
(*   end. *)

Global Instance add_hpoly : add_of (hpoly A) := addXn 0.
Global Instance sub_hpoly : sub_of (hpoly A) := fun p q => p + - q.

Definition shift_hpoly n (p : hpoly A) := PX 0 n p.

Global Instance mul_hpoly : mul_of (hpoly A) := fix f p q := match p, q with
  | Pc a, q => a *: q
  | p, Pc b => b *: p
  | PX a n p, PX b m q =>
     shift_hpoly (n + m) (f p q) + shift_hpoly m (a *: q) +
    (shift_hpoly n (b *: p) + Pc (a * b))
  end.

Fixpoint eq0_hpoly (p : hpoly A) : bool := match p with
  | Pc a      => (a == 0)%C
  | PX a n p' => (eq0_hpoly p') && (a == 0)%C
  end.

Global Instance eq_hpoly : eq_of (hpoly A) := fun p q => eq0_hpoly (p - q).

(* Alternative definition, should be used with normalize: *)
(* Fixpoint eq_hpoly_op p q {struct p} := match p, q with *)
(*   | Pc a, Pc b => (a == b)%C *)
(*   | PX a n p', PX b m q' => (a == b)%C && (cast n == cast m) && (eq_hpoly_op p' q') *)
(*   | _, _ => false *)
(*   end. *)

Fixpoint size_hpoly (p : hpoly A) : N :=
  if eq0_hpoly p then 0%C else match p with
  | Pc a => 1%C
  | PX a n p' => if eq0_hpoly p' then 1%C else (cast n + size_hpoly p')%C
  end.

Fixpoint lead_coef_hpoly (p : hpoly A) :=
  match p with
  | Pc a => a
  | PX a n p' => let b := lead_coef_hpoly p' in
                 if (b == 0)%C then a else b
  end.

(* Fixpoint split_hpoly (m : N) p : hpoly A * hpoly A := match p with *)
(*   | Pc a => (Pc a, Pc 0) *)
(*   | PX a n p' => if (m == 0)%C then (Pc 0,p) *)
(*     else let (p1,p2) := split_hpoly (m - cast n)%C p' in (PX a n p1, p2) *)
(*   end. *)

End hpoly_op.
End hpoly.

Parametricity hpoly.
Parametricity normalize.
Parametricity from_seq.
Parametricity cast_hpoly.
Parametricity zero_hpoly.
Parametricity one_hpoly.
Parametricity map_hpoly.
Parametricity opp_hpoly.
Parametricity scale_hpoly.
Parametricity addXn_const.
Parametricity addXn.
Parametricity add_hpoly.
Parametricity sub_hpoly.
Parametricity shift_hpoly.
Parametricity mul_hpoly.
Parametricity eq0_hpoly.
Parametricity eq_hpoly.
Parametricity size_hpoly.
Parametricity lead_coef_hpoly.

(******************************************************************************)
(** PART II: Proving correctness properties of the previously defined objects *)
(******************************************************************************)
Section hpoly_theory.

Variable A : comRingType.

Instance zeroA : zero_of A := 0%R.
Instance oneA  : one_of A  := 1%R.
Instance addA  : add_of A  := +%R.
Instance oppA  : opp_of A  := -%R.
Instance subA  : sub_of A  := fun x y => x - y.
Instance mulA  : mul_of A  := *%R.
Instance eqA   : eq_of A   := eqtype.eq_op.

Instance one_pos : one_of pos := posS 0.
Instance add_pos : add_of pos := fun m n => insubd (posS 0) (val m + val n)%N.
Instance sub_pos : sub_of pos := fun m n => insubd (posS 0) (val m - val n)%N.
Instance mul_pos : mul_of pos := fun m n => insubd (posS 0) (val m * val n)%N.
Instance eq_pos  : eq_of pos  := eqtype.eq_op.
(* Instance lt_pos  : lt pos  := fun m n => val m < val n. *)
Instance leq_pos : leq_of pos := fun m n => val m <= val n.

Instance zero_nat : zero_of nat := 0%N.
Instance eq_nat   : eq_of nat   := eqtype.eq_op.
(* Instance lt_nat   : lt nat   := ltn. *)
Instance leq_nat  : leq_of nat  := ssrnat.leq.
Instance add_nat  : add_of nat  := addn.
Instance sub_nat  : sub_of nat  := subn.

Instance cast_pos_nat : cast_of pos nat := val.
Instance cast_nat_pos : cast_of nat pos := insubd 1%C.

Fixpoint to_poly (p : hpoly A) := match p with
  | Pc c => c%:P
  | PX a n p => to_poly p * 'X^(cast (n : pos)) + a%:P
  end.

(* Global Instance spec_hpoly : spec_of (hpoly A pos) {poly A} := to_poly. *)

Definition to_hpoly : {poly A} -> (@hpoly pos A) := fun p => from_seq (polyseq p).

(* This instance has to be declared here in order not to make form_seq confused *)
Instance one_nat  : one_of nat  := 1%N.

Lemma to_hpolyK : cancel to_hpoly to_poly.
Proof.
elim/poly_ind; rewrite /to_hpoly ?polyseq0 // => p c ih.
rewrite -{1}cons_poly_def polyseq_cons.
have [|pn0] /= := nilP.
  rewrite -polyseq0 => /poly_inj ->; rewrite mul0r add0r.
  apply/poly_inj; rewrite !polyseqC.
   by case c0: (c == 0); rewrite ?polyseq0 // polyseqC c0.
by case: (polyseq p) ih => /= [<-| a l -> //]; rewrite mul0r add0r.
Qed.

Lemma ncons_add : forall m n (a : A) p,
  ncons (m + n) a p = ncons m a (ncons n a p).
Proof. by elim=> //= m ih n a p; rewrite ih. Qed.

Lemma normalizeK : forall p, to_poly (normalize p) = to_poly p.
Proof.
elim => //= a n p <-; case: (normalize p) => //= b m q.
case: ifP => //= /eqP ->; case: n => [[]] //= n n0.
by rewrite addr0 /cast /cast_pos_nat insubdK /= ?exprD ?mulrA ?addnS.
Qed.

Definition Rhpoly : {poly A} -> hpoly A -> Type := fun_hrel to_poly.

(* This is OK here, but not everywhere *)
Instance refines_eq_refl A (x : A) : refines Logic.eq x x | 999.
Proof. by rewrite refinesE. Qed.

Lemma RhpolyE p q : refines Rhpoly p q -> p = to_poly q.
Proof. by rewrite refinesE. Qed.

Instance Rhpolyspec_r x : refines Rhpoly (to_poly x) x | 10000.
Proof. by rewrite !refinesE; case: x. Qed.

Fact normalize_lock : unit. Proof. exact tt. Qed.
Definition normalize_id := locked_with normalize_lock (@id {poly A}).
Lemma normalize_idE p : normalize_id p = p.
Proof. by rewrite /normalize_id unlock. Qed.

Local Open Scope rel_scope.

Instance Rhpoly_normalize : refines (Rhpoly ==> Rhpoly) normalize_id normalize.
Proof.
by rewrite refinesE => p hp rp; rewrite /Rhpoly /fun_hrel normalizeK normalize_idE.
Qed.

Instance Rhpoly_cast : refines (eq ==> Rhpoly) (fun x => x%:P) cast.
Proof.
  by rewrite refinesE=> _ x ->; rewrite /Rhpoly /fun_hrel /cast /cast_hpoly /=.
Qed.

(* zero and one *)
Instance Rhpoly_0 : refines Rhpoly 0%R 0%C.
Proof. by rewrite refinesE. Qed.

Instance Rhpoly_1 : refines Rhpoly 1%R 1%C.
Proof. by rewrite refinesE. Qed.

Lemma to_poly_shift : forall n p, to_poly p * 'X^(cast n) = to_poly (PX 0 n p).
Proof. by case; elim => //= n ih h0 hp; rewrite addr0. Qed.

Instance Rhpoly_opp : refines (Rhpoly ==> Rhpoly) -%R -%C.
Proof.
apply refines_abstr => p hp h1.
rewrite [p]RhpolyE refinesE /Rhpoly /fun_hrel {p h1}.
by elim: hp => /= [a|a n p ->]; rewrite polyC_opp // opprD mulNr.
Qed.

Instance Rhpoly_scale : refines (Logic.eq ==> Rhpoly ==> Rhpoly) *:%R *:%C.
Proof.
rewrite refinesE => /= a b -> p hp h1.
rewrite [p]RhpolyE /Rhpoly /fun_hrel {a p h1}.
elim: hp => [a|a n p ih] /=; first by rewrite polyC_mul mul_polyC.
by rewrite ih polyC_mul -!mul_polyC mulrDr mulrA.
Qed.

Lemma addXn_constE n a q : to_poly (addXn_const n a q) = a%:P * 'X^n + to_poly q.
Proof.
elim: q n => [b [|n]|b m q' ih n] /=; simpC; first by rewrite polyC_add expr0 mulr1.
  by rewrite /cast /cast_pos_nat insubdK.
case: eqP => [->|/eqP n0] /=; first by rewrite polyC_add expr0 mulr1 addrCA.
case: eqP => [hn|hnc] /=; first by rewrite ih expr0 mulr1 -hn mulrDl -addrA.
rewrite [(_ <= _)%C]/((_ <= _)%N) subn_eq0.
have [hleq|hlt] /= := leqP n (cast m); rewrite /cast /cast_nat_pos /cast_pos_nat.
  rewrite insubdK -?topredE /= ?lt0n // mulrDl -mulrA -exprD addrCA -addrA.
  rewrite ?insubdK -?topredE /= ?subn_gt0 ?lt0n ?subnK // ltn_neqAle.
  by move/eqP: hnc=> ->.
by rewrite ih mulrDl -mulrA -exprD subnK ?addrA // ltnW.
Qed.

Arguments addXn_const _ _ _ _ _ _ _ _ _ _ _ n a q : simpl never.

Lemma addXnE n p q : to_poly (addXn n p q) = to_poly p * 'X^n + to_poly q.
Proof.
elim: p n q => [a n q|a n' p ih n [b|b m q]] /=; simpC; first by rewrite addXn_constE.
  case: eqP => [->|/eqP n0]; first by rewrite expr0 mulr1 /= polyC_add addrA.
  by rewrite /= /cast /cast_pos_nat /cast_nat_pos insubdK // -topredE /= lt0n.
case: eqP => [->|/eqP no].
  rewrite expr0 mulr1 /leq_op /leq_pos /eq_op /eq_pos.
  case: ifP => [/eqP ->|hneq] /=.
    by rewrite ih expr0 mulr1 mulrDl polyC_add -!addrA [_ + (a%:P + _)]addrCA.
  rewrite hneq.
  have [hlt|hleq] /= := leqP (val_of_pos n') (val_of_pos m);
    rewrite ih polyC_add mulrDl -!addrA ?expr0.
    rewrite mulr1 /= addr0 -mulrA -exprD [_ + (a%:P + _)]addrCA /cast.
    rewrite /cast_pos_nat insubdK ?subnK -?topredE /= ?subn_gt0 // ltn_neqAle.
    by move/eqP/eqP: hneq=> ->.
  rewrite -mulrA -exprD [_ + (a%:P + _)]addrCA /cast /cast_pos_nat.
  rewrite  insubdK ?subnK // -?topredE /=; first by rewrite ltnW.
  by rewrite subn_gt0.
rewrite !ih !addXn_constE expr0 mulr1 /= addr0 mulrDl -mulrA -exprD addnC.
by rewrite -!addrA [b%:P + (_ + _)]addrCA [b%:P + _]addrC.
Qed.

Instance Rhpoly_add : refines (Rhpoly ==> Rhpoly ==> Rhpoly) +%R (add_hpoly (N:=nat)).
Proof.
apply refines_abstr2 => p hp h1 q hq h2.
rewrite [p]RhpolyE [q]RhpolyE refinesE /Rhpoly /fun_hrel {p q h1 h2}.
by rewrite /add_op /add_hpoly addXnE expr0 mulr1.
Qed.

Lemma to_poly_scale a p : to_poly (a *: p)%C = a *: (to_poly p).
Proof.
  elim: p=> [b|b n p ih] /=;
    rewrite /mul_op /mulA -mul_polyC polyC_mul //.
  by rewrite ih -mul_polyC mulrDr mulrA /mul_op /mulA.
Qed.

Instance Rhpoly_mul : refines (Rhpoly ==> Rhpoly ==> Rhpoly) *%R (mul_hpoly (N:=nat)).
Proof.
apply refines_abstr2 => p hp h1 q hq h2.
rewrite [p]RhpolyE [q]RhpolyE refinesE /Rhpoly /fun_hrel {p q h1 h2}.
elim: hp hq => [a [b|b m l']|a n l ih [b|b m l']] /=;
      first by rewrite polyC_mul.
    by rewrite polyC_mul to_poly_scale -mul_polyC mulrDr mulrA.
  by rewrite polyC_mul to_poly_scale -mul_polyC mulrDl -mulrA mulrC
             [(_%:P * _%:P)]mulrC.
rewrite mulrDr !mulrDl mulrCA -!mulrA -exprD mulrCA !mulrA [_ * b%:P]mulrC.
rewrite -polyC_mul !mul_polyC !addXnE /= expr0 !mulr1 !addr0 ih scalerAl /cast.
rewrite !to_poly_scale /cast_pos_nat insubdK -?topredE //= addn_gt0.
by case: n=> n /= ->.
Qed.

Instance Rhpoly_sub :
  refines (Rhpoly ==> Rhpoly ==> Rhpoly) (fun x y => x - y) (sub_hpoly (N:=nat)).
Proof.
apply refines_abstr2 => p hp h1 q hq h2.
by rewrite refinesE /sub_hpoly /Rhpoly /fun_hrel [_ - _]RhpolyE.
Qed.

Instance Rhpoly_shift : refines (Logic.eq ==> Rhpoly ==> Rhpoly)
  (fun n p => p * 'X^(cast n)) (fun n p => shift_hpoly n p).
Proof.
rewrite refinesE => /= a n -> p hp h1.
by rewrite [p]RhpolyE /Rhpoly /fun_hrel {a p h1} /= addr0.
Qed.

(* Add to ssr? *)
Lemma size_MXnaddC (R : comRingType) (p : {poly R}) (c : R) n :
  size (p * 'X^n.+1 + c%:P) = if (p == 0) then size c%:P else (n.+1 + size p)%N.
Proof.
have [->|/eqP hp0] := eqP; first by rewrite mul0r add0r.
rewrite size_addl polyseqMXn ?size_ncons // size_polyC.
by case: (c == 0)=> //=; rewrite ltnS ltn_addl // size_poly_gt0.
Qed.

Instance Rhpoly_eq0 :
  refines (Rhpoly ==> bool_R) (fun p => 0 == p) eq0_hpoly.
Proof.
  rewrite refinesE => p hp rp; rewrite [p]RhpolyE {p rp} eq_sym.
  have -> : (to_poly hp == 0) = (eq0_hpoly hp).
    elim: hp => [a|a n p ih] /=; first by rewrite polyC_eq0.
    rewrite /cast /cast_pos_nat /=; case: n=> n ngt0.
    rewrite /val_of_pos -[n]prednK // -size_poly_eq0 size_MXnaddC -ih prednK //.
    case: ifP=> /=; first by rewrite size_poly_eq0 polyC_eq0.
    by rewrite addn_eq0 size_poly_eq0 andbC=> ->.
  exact: bool_Rxx.
Qed.

Instance Rhpoly_eq : refines (Rhpoly ==> Rhpoly ==> bool_R)
                             eqtype.eq_op (eq_hpoly (N:=nat)).
Proof.
  apply refines_abstr2=> p hp h1 q hq h2.
  rewrite /eq_hpoly refinesE -subr_eq0 eq_sym [_ == _]refines_eq.
  exact: bool_Rxx.
Qed.

Instance Rhpoly_size : refines (Rhpoly ==> Logic.eq) size size_hpoly.
Proof.
  apply refines_abstr=> p hp h1; rewrite [p]RhpolyE refinesE {p h1}.
  elim: hp=> [a|a n p ih] /=; first by rewrite size_polyC; simpC; case: eqP.
  rewrite /cast /cast_pos_nat /=; case: n=> n ngt0.
  rewrite /val_of_pos -[n]prednK // size_MXnaddC ih prednK // eq_sym
          [_ == _]refines_eq.
  by case: ifP=> //=; simpC; rewrite size_polyC; case: ifP.
Qed.

Lemma lead_coef_MXnaddC (R : comRingType) (p : {poly R}) (c : R) n :
  lead_coef (p * 'X^n.+1 + c%:P) = if (lead_coef p == 0) then c
                                   else lead_coef p.
Proof.
  have [|/eqP hp0] := eqP.
    move/eqP; rewrite lead_coef_eq0; move/eqP=> ->.
    by rewrite mul0r add0r lead_coefC.
  rewrite lead_coefDl; first by rewrite lead_coef_Mmonic ?monicXn.
  rewrite size_polyC size_Mmonic ?monicXn -?lead_coef_eq0 //.
  rewrite size_polyXn !addnS -pred_Sn.
  case: (c == 0)=> //=.
  by rewrite ltnS ltn_addr // size_poly_gt0 -lead_coef_eq0.
Qed.

Instance Rhpoly_lead_coef : refines (Rhpoly ==> Logic.eq)
                                    lead_coef lead_coef_hpoly.
Proof.
  rewrite refinesE=> _ hp <-.
  elim: hp=> [a|a n p ih] /=; first by rewrite lead_coefC.
  rewrite -ih /cast /cast_pos_nat /=; case: n=> n ngt0.
  by rewrite /val_of_pos -[n]prednK // lead_coef_MXnaddC.
Qed.

(*************************************************************************)
(* PART III: Parametricity part                                          *)
(*************************************************************************)
Section hpoly_parametricity.

Import Refinements.Op.

Context (C : Type) (rAC : A -> C -> Prop).
Context (P : Type) (rP : pos -> P -> Prop).
Context (N : Type) (rN : nat -> N -> Prop).
Context `{zero_of C, one_of C, opp_of C, add_of C, sub_of C, mul_of C, eq_of C}.
Context `{one_of P, add_of P, sub_of P, eq_of P(* , lt P *), leq_of P}.
Context `{zero_of N, one_of N, eq_of N(* , lt N *), leq_of N, add_of N, sub_of N}.
Context `{cast_of N P, cast_of P N}.
Context `{!refines rAC 0%R 0%C, !refines rAC 1%R 1%C}.
Context `{!refines (rAC ==> rAC) -%R -%C}.
Context `{!refines (rAC ==> rAC ==> rAC) +%R +%C}.
Context `{!refines (rAC ==> rAC ==> rAC) (fun x y => x - y) sub_op}.
Context `{!refines (rAC ==> rAC ==> rAC) *%R *%C}.
Context `{!refines (rAC ==> rAC ==> bool_R) eqtype.eq_op eq_op}.
Context `{!refines rP pos1 1%C}.
Context `{!refines (rP ==> rP ==> rP) add_pos +%C}.
Context `{!refines (rP ==> rP ==> rP) sub_pos sub_op}.
Context `{!refines (rP ==> rP ==> bool_R) eqtype.eq_op eq_op}.
(* Context `{!refines (rP ==> rP ==> Logic.eq) lt_pos lt_op}. *)
Context `{!refines (rP ==> rP ==> bool_R) leq_pos leq_op}.
Context `{!refines rN 0%N 0%C, !refines rN 1%N 1%C}.
Context `{!refines (rN ==> rN ==> rN) addn +%C}.
Context `{!refines (rN ==> rN ==> rN) subn sub_op}.
Context `{!refines (rN ==> rN ==> bool_R) eqtype.eq_op eq_op}.
(* Context `{!refines (rN ==> rN ==> Logic.eq) ltn lt_op}. *)
Context `{!refines (rN ==> rN ==> bool_R) ssrnat.leq leq_op}.
Context `{!refines (rN ==> rP) cast_nat_pos cast}.
Context `{!refines (rP ==> rN) cast_pos_nat cast}.

Definition RhpolyC := (Rhpoly \o (hpoly_R rP rAC)).

Global Instance RhpolyC_0 : refines RhpolyC 0%R 0%C.
Proof. param_comp zero_hpoly_R. Qed.

Global Instance RhpolyC_1 : refines RhpolyC 1%R 1%C.
Proof. param_comp one_hpoly_R. Qed.

Global Instance RhpolyC_add : refines (RhpolyC ==> RhpolyC ==> RhpolyC)
                                      +%R (add_hpoly (N:=N)).
Proof. param_comp add_hpoly_R. Qed.

Global Instance RhpolyC_opp : refines (RhpolyC ==> RhpolyC) -%R -%C.
Proof. param_comp opp_hpoly_R. Qed.

Global Instance RhpolyC_scale : refines (rAC ==> RhpolyC ==> RhpolyC) *:%R *:%C.
Proof. param_comp scale_hpoly_R. Qed.

Global Instance RhpolyC_sub : refines (RhpolyC ==> RhpolyC ==> RhpolyC)
                                      (fun x y => x - y) (sub_hpoly (N:=N)).
Proof. param_comp sub_hpoly_R. Qed.

Global Instance RhpolyC_shift : refines (rP ==> RhpolyC ==> RhpolyC)
  (fun n p => p * 'X^(cast n)) (fun n (p : hpoly C) => shift_hpoly n p).
Proof. param_comp shift_hpoly_R. Qed.

Global Instance RhpolyC_mul :
  refines (RhpolyC ==> RhpolyC ==> RhpolyC) *%R (mul_hpoly (N:=N)).
Proof. param_comp mul_hpoly_R. Qed.

(* Global Instance RhpolyC_size : refines (RhpolyC ==> nat_R) size size_hpoly. *)
(* Proof. admit. Qed. *)
(* Proof. exact: param_trans. Qed. *)

Global Instance RhpolyC_lead_coef :
  refines (RhpolyC ==> rAC) lead_coef lead_coef_hpoly.
Proof. param_comp lead_coef_hpoly_R. Qed.

Global Instance RhpolyC_polyC :
  refines (rAC ==> RhpolyC) (fun a => a%:P) cast.
Proof. param_comp cast_hpoly_R. Qed.

Global Instance RhpolyC_eq : refines (RhpolyC ==> RhpolyC ==> bool_R)
                                     eqtype.eq_op (eq_hpoly (N:=N)).
Proof. param_comp eq_hpoly_R. Qed.

(* Global Instance RhpolyC_horner : param (RhpolyC ==> rAC ==> rAC) *)
(*   (fun p x => p.[x]) (fun sp x => horner_seq sp x). *)
(* Proof. admit. Qed. *)
(* (* Proof. exact: param_trans. Qed. *) *)

End hpoly_parametricity.
End hpoly_theory.