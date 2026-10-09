import Std.Tactic

/-!
Transaction-level specification for the Board1 public token machine.

This file deliberately specifies only the ideal machine.  It does not claim
that the production SystemVerilog refines this specification; that is a
separate RTL/netlist proof obligation.
-/

namespace Board1.PublicSurface

abbrev Token := Fin 4019

def modelContext : Nat := 2048
def tapeCapacity : Nat := 2049

theorem tapeCapacity_eq : tapeCapacity = modelContext + 1 := by
  rfl

/-- The complete set of accepted application-level commands. -/
inductive Command where
  | append (token : Token)
  | step
  | clear
deriving DecidableEq, Repr

/-- A completed transaction produces exactly one of these replies. -/
inductive Reply where
  | appendAccepted
  | generated (token : Token)
  | clearAccepted
deriving DecidableEq, Repr

/-- Abstract public state.  Internal K/V, arithmetic, and memory state is hidden. -/
structure State where
  tape : List Token
deriving DecidableEq, Repr

def State.WellFormed (state : State) : Prop :=
  state.tape.length <= tapeCapacity

def initial : State := { tape := [] }

theorem initial_wellFormed : initial.WellFormed := by
  simp [State.WellFormed, initial, tapeCapacity]

/--
Execute one accepted transaction.  `nextToken` represents the one fixed,
deterministic model.  `none` means that the command is not currently accepted:
APPEND requires room below position 2,048 and STEP requires a nonempty tape of
at most 2,048 tokens.  A successful STEP appends its returned token, so the
2,049th physical slot can hold the result of stepping at model position 2,047.
-/
def execute (nextToken : List Token -> Token) (state : State) :
    Command -> Option (State × Reply)
  | .append token =>
      if state.tape.length < modelContext then
        some ({ tape := state.tape ++ [token] }, .appendAccepted)
      else
        none
  | .step =>
      if 0 < state.tape.length ∧ state.tape.length <= modelContext then
        let token := nextToken state.tape
        some ({ tape := state.tape ++ [token] }, .generated token)
      else
        none
  | .clear =>
      some (initial, .clearAccepted)

theorem command_exhaustive (command : Command) :
    (Exists fun token => command = .append token) ∨
      command = .step ∨ command = .clear := by
  cases command with
  | append token => exact Or.inl ⟨token, rfl⟩
  | step => exact Or.inr (Or.inl rfl)
  | clear => exact Or.inr (Or.inr rfl)

theorem execute_preserves_wellFormed
    (nextToken : List Token -> Token)
    (state nextState : State)
    (command : Command)
    (reply : Reply)
    (hExecute : execute nextToken state command = some (nextState, reply)) :
    nextState.WellFormed := by
  cases command with
  | append token =>
      simp only [execute] at hExecute
      split at hExecute
      next hCapacity =>
        simp only [Option.some.injEq, Prod.mk.injEq] at hExecute
        rcases hExecute with ⟨hNext, hReply⟩
        subst nextState
        subst reply
        simp only [State.WellFormed, List.length_append, List.length_cons,
          List.length_nil]
        simp only [modelContext] at hCapacity
        simp only [tapeCapacity]
        omega
      next => simp at hExecute
  | step =>
      simp only [execute] at hExecute
      split at hExecute
      next hCapacity =>
        simp only [Option.some.injEq, Prod.mk.injEq] at hExecute
        rcases hExecute with ⟨hNext, hReply⟩
        subst nextState
        subst reply
        simp only [State.WellFormed, List.length_append, List.length_cons,
          List.length_nil]
        simp only [modelContext] at hCapacity
        simp only [tapeCapacity]
        omega
      next => simp at hExecute
  | clear =>
      simp only [execute, Option.some.injEq, Prod.mk.injEq] at hExecute
      rcases hExecute with ⟨hNext, hReply⟩
      subst nextState
      subst reply
      exact initial_wellFormed

theorem append_effect
    (nextToken : List Token -> Token)
    (state nextState : State)
    (token : Token)
    (reply : Reply)
    (hExecute : execute nextToken state (.append token) =
      some (nextState, reply)) :
    nextState.tape = state.tape ++ [token] ∧ reply = .appendAccepted := by
  simp only [execute] at hExecute
  split at hExecute
  next =>
    simp only [Option.some.injEq, Prod.mk.injEq] at hExecute
    rcases hExecute with ⟨hNext, hReply⟩
    subst nextState
    subst reply
    exact ⟨rfl, rfl⟩
  next => simp at hExecute

theorem step_effect
    (nextToken : List Token -> Token)
    (state nextState : State)
    (reply : Reply)
    (hExecute : execute nextToken state .step = some (nextState, reply)) :
    nextState.tape = state.tape ++ [nextToken state.tape] ∧
      reply = .generated (nextToken state.tape) := by
  simp only [execute] at hExecute
  split at hExecute
  next =>
    simp only [Option.some.injEq, Prod.mk.injEq] at hExecute
    rcases hExecute with ⟨hNext, hReply⟩
    subst nextState
    subst reply
    exact ⟨rfl, rfl⟩
  next => simp at hExecute

theorem clear_effect
    (nextToken : List Token -> Token)
    (state nextState : State)
    (reply : Reply)
    (hExecute : execute nextToken state .clear = some (nextState, reply)) :
    nextState = initial ∧ reply = .clearAccepted := by
  simp only [execute, Option.some.injEq, Prod.mk.injEq] at hExecute
  exact ⟨hExecute.1.symm, hExecute.2.symm⟩

theorem append_requires_capacity
    (nextToken : List Token -> Token)
    (state nextState : State)
    (token : Token)
    (reply : Reply)
    (hExecute : execute nextToken state (.append token) =
      some (nextState, reply)) :
    state.tape.length < modelContext := by
  simp only [execute] at hExecute
  split at hExecute <;> simp_all

theorem step_requires_nonempty_model_context
    (nextToken : List Token -> Token)
    (state nextState : State)
    (reply : Reply)
    (hExecute : execute nextToken state .step = some (nextState, reply)) :
    0 < state.tape.length ∧ state.tape.length <= modelContext := by
  simp only [execute] at hExecute
  split at hExecute <;> simp_all

theorem clear_always_accepted
    (nextToken : List Token -> Token) (state : State) :
    execute nextToken state .clear = some (initial, .clearAccepted) := by
  rfl

/-- Execute a finite sequence of accepted public transactions. -/
def run (nextToken : List Token -> Token) (state : State) :
    List Command -> Option (State × List Reply)
  | [] => some (state, [])
  | command :: commands =>
      match execute nextToken state command with
      | none => none
      | some (nextState, reply) =>
          match run nextToken nextState commands with
          | none => none
          | some (finalState, replies) =>
              some (finalState, reply :: replies)

theorem run_preserves_wellFormed
    (nextToken : List Token -> Token)
    (state finalState : State)
    (commands : List Command)
    (replies : List Reply)
    (hState : state.WellFormed)
    (hRun : run nextToken state commands = some (finalState, replies)) :
    finalState.WellFormed := by
  induction commands generalizing state finalState replies with
  | nil =>
      simp only [run, Option.some.injEq, Prod.mk.injEq] at hRun
      exact hRun.1 ▸ hState
  | cons command commands ih =>
      cases hExecute : execute nextToken state command with
      | none => simp [run, hExecute] at hRun
      | some result =>
          rcases result with ⟨nextState, reply⟩
          cases hTail : run nextToken nextState commands with
          | none => simp [run, hExecute, hTail] at hRun
          | some result =>
              rcases result with ⟨tailState, tailReplies⟩
              simp only [run, hExecute, hTail, Option.some.injEq,
                Prod.mk.injEq] at hRun
              rcases hRun with ⟨hFinal, hReplies⟩
              subst finalState
              subst replies
              exact ih nextState tailState tailReplies
                (execute_preserves_wellFormed nextToken state nextState command
                  reply hExecute)
                hTail

theorem run_reply_count
    (nextToken : List Token -> Token)
    (state finalState : State)
    (commands : List Command)
    (replies : List Reply)
    (hRun : run nextToken state commands = some (finalState, replies)) :
    replies.length = commands.length := by
  induction commands generalizing state finalState replies with
  | nil =>
      simp only [run, Option.some.injEq, Prod.mk.injEq] at hRun
      simp [hRun.2]
  | cons command commands ih =>
      cases hExecute : execute nextToken state command with
      | none => simp [run, hExecute] at hRun
      | some result =>
          rcases result with ⟨nextState, reply⟩
          cases hTail : run nextToken nextState commands with
          | none => simp [run, hExecute, hTail] at hRun
          | some result =>
              rcases result with ⟨tailState, tailReplies⟩
              simp only [run, hExecute, hTail, Option.some.injEq,
                Prod.mk.injEq] at hRun
              rcases hRun with ⟨hFinal, hReplies⟩
              subst finalState
              subst replies
              simp only [List.length_cons]
              exact congrArg Nat.succ
                (ih nextState tailState tailReplies hTail)

end Board1.PublicSurface
