Require Import Rupicola.Lib.Api.

Definition Comp A := A -> Prop.
Definition ret {A} (a: A) : Comp A := fun a' => a' = a.
Definition pick {A} (P: Comp A) := P.
Definition bind {A B} (v: Comp A) (body: A -> Comp B) : Comp B :=
  fun b => exists a, v a /\ body a b.
Definition bindn {A B} (vars: list string) (v: Comp A) (body: A -> Comp B) : Comp B :=
  bind v body.

Notation "'let/+' x 'as' nm := val 'in' body" :=
  (bindn [nm] val (fun x => body))
    (at level 200, x ident, body at level 200,
     format "'[hv' 'let/+'  x  'as'  nm  :=  val  'in' '//' body ']'").

Notation "'let/+' x := val 'in' body" :=
  (bindn [IdentParsing.TC.ident_to_string x] val (fun x => body))
    (at level 200, x ident, body at level 200,
     only parsing).

Notation "{ x | P }" := (pick (fun x => P)).

Require Import Coq.Init.Byte.

Section Sample.
  Context {semantics : Semantics.parameters}
          {semantics_ok : Semantics.parameters_ok _}.

  Definition pbind {A} (pred: A -> predicate) (c: Comp A) : predicate :=
    fun tr mem locals => exists a, c a /\ pred a tr mem locals.

  Lemma WeakestPrecondition_unbind {A B} funcs main t m l post
        (c: Comp A) (k: A -> Comp B) a0 :
    c a0 ->
    WeakestPrecondition.program funcs main t m l (pbind post (k a0)) ->
    WeakestPrecondition.program funcs main t m l (pbind post (bind c k)).
  Proof.
    unfold pbind, bind; intros * Hc;
      eapply WeakestPrecondition_weaken; eauto; cbv beta.
    clear - Hc; intros; firstorder.
  Qed.

  Lemma WeakestPrecondition_unbindn {A B} funcs main t m l post
        vars (c: Comp A) (k: A -> Comp B) a0 :
    c a0 ->
    (c a0 -> WeakestPrecondition.program funcs main t m l (pbind post (k a0))) ->
    WeakestPrecondition.program funcs main t m l (pbind post (bindn vars c k)).
  Proof.
    intros; eapply WeakestPrecondition_unbind; eauto.
  Qed.

  Definition Bag := list word.

  Definition bag_at (addr: word) (b: Bag) :=
    Lift1Prop.ex1 (fun bytes =>
                     emp (forall x, List.In x bytes <-> List.In x b) *
                     array scalar (word.of_Z (Memory.bytes_per_word Semantics.width))
                           addr bytes)%sep.

  Definition peek (l: Bag) := { x | List.In x l }.

  Lemma compile_peek {tr mem locals functions} (b: Bag) :
    let c := peek b in
    forall {B} {pred: B -> predicate}
      {k: word -> Comp B} {k_impl}
      R b_ptr b_var var,

      b <> [] ->
      (bag_at b_ptr b * R)%sep mem ->
      map.get locals b_var = Some b_ptr ->

      (forall v,
          c v ->
          <{ Trace := tr;
             Memory := mem;
             Locals := map.put locals var v;
             Functions := functions }>
          k_impl
          <{ pbind pred (k v) }>) ->
      <{ Trace := tr;
         Memory := mem;
         Locals := locals;
         Functions := functions }>
      cmd.seq (cmd.set var (expr.load access_size.word (expr.var b_var))) k_impl
      <{ pbind pred (bindn [var] c k) }>.
  Proof.
    destruct b as [|w b]; try congruence.
    intros * Hnn [ws [Hin Hm]%sep_assoc%sep_emp_l]%sep_ex1_l Hl Hk.
    destruct ws as [| w' ws]; [ exfalso; eapply Hin; red; eauto | ].
    eexists; split.
    - eexists; split; eauto.
      eexists; split; eauto.
      eapply load_word_of_sep.
      seprewrite_in uconstr:(@array_cons) Hm.
      ecancel_assumption.
    - eapply WeakestPrecondition_unbindn; [ | intros; apply Hk; eauto ].
      apply Hin; red; eauto.
  Qed.

  Definition nondet_sum_src (b: Bag) :=
    let/+ x := peek b in
    let/+ y := peek b in
    let/n out := word.add x y in
    ret out.

  Instance spec_of_nondet_sum : spec_of "nondet_sum" :=
    let pre b b_ptr R tr mem :=
        b <> [] /\
        (bag_at b_ptr b * R)%sep mem in
    let post b b_ptr R tr mem tr' mem' rets :=
        exists v, (nondet_sum_src b) v /\ tr' = tr /\
             rets = [v] /\ (bag_at b_ptr b * R)%sep mem' in
      fun functions =>
        forall b b_ptr R,
        forall tr mem,
          pre b b_ptr R tr mem ->
          WeakestPrecondition.call
            functions "nondet_sum" tr mem [b_ptr]
            (post b b_ptr R tr mem).

  Lemma compile_setup_nondet_pbind {tr mem locals functions} :
    forall {A} {pred: A -> _ -> predicate}
      {spec: Comp A} {cmd}
      retvars,

      (let pred a := wp_bind_retvars retvars (pred a) in
       <{ Trace := tr;
          Memory := mem;
          Locals := locals;
          Functions := functions }>
       cmd
       <{ pbind pred spec }>) ->
      <{ Trace := tr;
         Memory := mem;
         Locals := locals;
         Functions := functions }>
      cmd
      <{ (fun spec =>
            wp_bind_retvars
              retvars
              (fun rets tr' mem' locals' =>
                 exists a, spec a /\ pred a rets tr' mem' locals'))
           spec }>.
  Proof.
    intros; unfold pbind, wp_bind_retvars in *.
    use_hyp_with_matching_cmd; cbv beta in *.
    clear - H0; firstorder.
  Qed.

  Hint Unfold pbind: compiler.
  Hint Extern 1 (ret _ _) => reflexivity : compiler.
  Hint Resolve compile_setup_nondet_pbind : compiler_setup.
  Hint Extern 2 (IsRupicolaBinding (bindn _ _ _)) => exact true : typeclass_instances.

  Ltac compile_custom ::=
    simple eapply compile_peek.

  Derive nondet_sum_body SuchThat
         (defn! "nondet_sum"("b") ~> "out"
              { nondet_sum_body },
          implements nondet_sum_src)
  As nondet_sum_target_correct.
  Proof.
    compile.
  Qed.
End Sample.

(* Require Import bedrock2.NotationsCustomEntry. *)
(* Require Import bedrock2.NotationsInConstr. *)
(* Arguments nondet_sum_body /. *)
(* Eval simpl in nondet_sum_body. *)
