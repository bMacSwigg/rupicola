Require Import Rupicola.Lib.Core.
Require Import Rupicola.Lib.Notations.
Require Import Rupicola.Lib.Tactics.
Require Import Rupicola.Lib.Compiler.
Require Import Rupicola.Lib.Invariants.

Section Conditionals.
  Context {width: Z} {BW: Bitwidth width} {word: word.word width} {memT: map.map word Byte.byte}.
  Context {localsT: map.map String.string word}.
  Context {env: map.map String.string (list String.string * list String.string * Syntax.cmd)}.
  Context {ext_spec: bedrock2.Semantics.ExtSpec}.
  Context {word_ok : word.ok word} {mem_ok : map.ok memT}.
  Context {locals_ok : map.ok localsT}.
  Context {env_ok : map.ok env}.
  Context {ext_spec_ok : Semantics.ext_spec.ok ext_spec}.

  Definition nlet_id {A} {v: A} : nlet_eq_k (fun _ => A) v := fun x _ => x.

  (* TODO add FAQ entry on nlet_eq here (plus no let t := t since that's not compiled yet) *)
  Lemma compile_if {tr mem locals functions} (c: bool) {A} (t f: A) :
    let v := if c then t else f in
    forall {P} {pred: P v -> predicate} {val_pred: A -> predicate}
      {k: nlet_eq_k P v} {k_impl t_impl f_impl}
      c_expr vars,

      WeakestPrecondition.dexpr mem locals c_expr (word.b2w c) ->

      (let val_pred := val_pred in
       c = true ->
       <{ Trace := tr;
          Memory := mem;
          Locals := locals;
          Functions := functions }>
       t_impl
       <{ val_pred (nlet_eq vars t nlet_id) }>) ->
      (let val_pred := val_pred in
       c = false ->
       <{ Trace := tr;
          Memory := mem;
          Locals := locals;
          Functions := functions }>
       f_impl
       <{ val_pred (nlet_eq vars f nlet_id) }>) ->
      (let v := v in
       forall tr mem locals,
         val_pred v tr mem locals ->
       <{ Trace := tr;
          Memory := mem;
          Locals := locals;
          Functions := functions }>
       k_impl
       <{ pred (k v eq_refl) }>) ->
      <{ Trace := tr;
         Memory := mem;
         Locals := locals;
         Functions := functions }>
      cmd.seq
        (cmd.cond c_expr t_impl f_impl)
        k_impl
      <{ pred (nlet_eq vars v k) }>.
  Proof.
    intros * Hc Ht Hf Hk.
    repeat straightline.
    split_if ltac:(repeat straightline'); subst_lets_in_goal.
    eassumption.
    all: rewrite word.unsigned_b2w; cbv [Z.b2z].
    all: destruct_one_match; try congruence; [ ]; intros.
    all: eapply compile_seq; eauto.
  Qed.

  Lemma compile_tail_if {tr mem locals functions} (c: bool) {A} (t f: A) :
    let v := if c then t else f in
    forall {pred: A -> predicate} {t_impl f_impl}
      c_expr,

      WeakestPrecondition.dexpr mem locals c_expr (word.b2w c) ->

      (c = true ->
       <{ Trace := tr;
          Memory := mem;
          Locals := locals;
          Functions := functions }>
       t_impl
       <{ pred t }>) ->
      (c = false ->
       <{ Trace := tr;
          Memory := mem;
          Locals := locals;
          Functions := functions }>
       f_impl
       <{ pred f }>) ->
      <{ Trace := tr;
         Memory := mem;
         Locals := locals;
         Functions := functions }>
      cmd.cond c_expr t_impl f_impl
      <{ pred v }>.
  Proof.
    intros * Hc Ht Hf.
    repeat straightline'.
    split_if ltac:(repeat straightline'); subst_lets_in_goal.
    eassumption.
    all: rewrite word.unsigned_b2w; cbv [Z.b2z].
    all: destruct_one_match; try congruence; [ ]; intros.
    all: eauto.
  Qed.
End Conditionals.

Ltac compile_if :=
  let vp := infer_val_predicate in
  simple eapply compile_if with (val_pred := vp).

#[export] Hint Extern 2 (IsRupicolaBinding (if _ then _ else _)) =>
  exact true : typeclass_instances.

#[export] Hint Extern 1 =>
  simple eapply compile_tail_if; shelve : compiler.

#[export] Hint Extern 1
 (WeakestPrecondition.cmd _ _ _ _ _ (_ (nlet_eq _ (if _ then _ else _) _))) =>
  compile_if; shelve : compiler.
