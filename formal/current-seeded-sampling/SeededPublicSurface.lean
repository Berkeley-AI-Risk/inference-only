import Std.Tactic

/-!
Four-operation transaction specification. The fixed model's numerical sampler
and random transition are parameters held fixed for an entire run. This file
does not import RTL and does not claim an RTL refinement or CDF theorem.
Busy/stalls/faults and the shell's empty-boundary certificate are separate RTL
obligations. Here every call is an atomic transaction boundary.
-/
namespace Board1.SeededPublicSurface

abbrev Token := Fin 4019
abbrev Seed := Fin (2 ^ 128)
def modelContext : Nat := 2048
def tapeCapacity : Nat := 2049
def defaultSeed : Seed := ⟨1, by decide⟩
def normalizeSeed (seed : Seed) : Seed := if seed.val = 0 then defaultSeed else seed

inductive Temperature where
  | greedy | half | one | two
deriving DecidableEq, Repr

inductive Command where
  | append (token : Token)
  | step
  | clear
  | settings (temperature : Temperature) (seed : Seed)
deriving DecidableEq, Repr

inductive Reply where
  | appendAccepted | generated (token : Token) | clearAccepted | settingsAccepted
deriving DecidableEq, Repr

/-- All three functions are fixed circuit parameters, never command operands. -/
structure FixedFunctions where
  greedy : List Token → Token
  sample : List Token → Temperature → Seed → Token
  nextRandom : Seed → Seed

structure State where
  tape : List Token
  temperature : Temperature
  seed : Seed
  random : Seed
deriving DecidableEq, Repr

def State.WellFormed (state : State) : Prop := state.tape.length ≤ tapeCapacity
def initial : State := ⟨[], .greedy, defaultSeed, defaultSeed⟩
def cleared (state : State) : State := { state with tape := [], random := state.seed }
def selection (fixed : FixedFunctions) (state : State) : Token × Seed :=
  if state.temperature = .greedy then (fixed.greedy state.tape, state.random)
  else (fixed.sample state.tape state.temperature state.random, fixed.nextRandom state.random)

def execute (fixed : FixedFunctions) (state : State) : Command → Option (State × Reply)
  | .append token =>
      if state.tape.length < modelContext then
        some ({ state with tape := state.tape ++ [token] }, .appendAccepted)
      else none
  | .step =>
      if 0 < state.tape.length ∧ state.tape.length ≤ modelContext then
        let picked := selection fixed state
        some ({ state with tape := state.tape ++ [picked.1], random := picked.2 }, .generated picked.1)
      else none
  | .clear => some (cleared state, .clearAccepted)
  | .settings temperature seed =>
      if state.tape = [] then
        some (⟨[], temperature, normalizeSeed seed, normalizeSeed seed⟩, .settingsAccepted)
      else none

theorem initial_wellFormed : initial.WellFormed := by
  simp [initial, State.WellFormed, tapeCapacity]

theorem command_exhaustive (command : Command) :
    (∃ token, command = .append token) ∨ command = .step ∨ command = .clear ∨
    (∃ temperature seed, command = .settings temperature seed) := by
  cases command with
  | append token => exact Or.inl ⟨token, rfl⟩
  | step => exact Or.inr (Or.inl rfl)
  | clear => exact Or.inr (Or.inr (Or.inl rfl))
  | settings temperature seed => exact Or.inr (Or.inr (Or.inr ⟨temperature, seed, rfl⟩))

theorem execute_preserves_wellFormed (fixed : FixedFunctions) (state next : State)
    (command : Command) (reply : Reply)
    (h : execute fixed state command = some (next, reply)) : next.WellFormed := by
  cases command with
  | append token =>
      simp only [execute] at h
      split at h
      next bound =>
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        simp only [State.WellFormed, List.length_append, List.length_cons, List.length_nil]
        simp only [modelContext] at bound
        simp only [tapeCapacity]
        omega
      next => simp at h
  | step =>
      simp only [execute] at h
      split at h
      next bound =>
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        simp only [State.WellFormed, List.length_append, List.length_cons, List.length_nil]
        simp only [modelContext] at bound
        simp only [tapeCapacity]
        omega
      next => simp at h
  | clear =>
      simp only [execute, Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      simp [cleared, State.WellFormed, tapeCapacity]
  | settings temperature seed =>
      simp only [execute] at h
      split at h
      next =>
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        simp [State.WellFormed, tapeCapacity]
      next => simp at h

theorem settings_requires_empty (fixed : FixedFunctions) (state next : State)
    (temperature : Temperature) (seed : Seed) (reply : Reply)
    (h : execute fixed state (.settings temperature seed) = some (next, reply)) : state.tape = [] := by
  simp only [execute] at h
  split at h <;> simp_all

theorem append_requires_capacity (fixed : FixedFunctions) (state next : State)
    (token : Token) (reply : Reply)
    (h : execute fixed state (.append token) = some (next, reply)) : state.tape.length < modelContext := by
  simp only [execute] at h
  split at h <;> simp_all

theorem step_requires_context (fixed : FixedFunctions) (state next : State) (reply : Reply)
    (h : execute fixed state .step = some (next, reply)) :
    0 < state.tape.length ∧ state.tape.length ≤ modelContext := by
  simp only [execute] at h
  split at h <;> simp_all

theorem settings_effect (fixed : FixedFunctions) (state next : State)
    (temperature : Temperature) (seed : Seed) (reply : Reply)
    (h : execute fixed state (.settings temperature seed) = some (next, reply)) :
    next.tape = [] ∧ next.temperature = temperature ∧ next.seed = normalizeSeed seed ∧
    next.random = normalizeSeed seed ∧ reply = .settingsAccepted := by
  simp only [execute] at h
  split at h
  next =>
    simp only [Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  next => simp at h

theorem clear_effect (fixed : FixedFunctions) (state : State) :
    execute fixed state .clear = some (cleared state, .clearAccepted) ∧
    (cleared state).tape = [] ∧ (cleared state).temperature = state.temperature ∧
    (cleared state).seed = state.seed ∧ (cleared state).random = state.seed := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem append_preserves_sampling (fixed : FixedFunctions) (state next : State)
    (token : Token) (reply : Reply)
    (h : execute fixed state (.append token) = some (next, reply)) :
    next.temperature = state.temperature ∧ next.seed = state.seed ∧ next.random = state.random := by
  simp only [execute] at h
  split at h
  next =>
    simp only [Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨rfl, rfl, rfl⟩
  next => simp at h

theorem greedy_preserves_random (fixed : FixedFunctions) (state next : State) (reply : Reply)
    (greedy : state.temperature = .greedy)
    (h : execute fixed state .step = some (next, reply)) : next.random = state.random := by
  simp only [execute] at h
  split at h
  next =>
    simp only [Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simp [selection, greedy]
  next => simp at h

theorem positive_advances_random (fixed : FixedFunctions) (state next : State) (reply : Reply)
    (positive : state.temperature ≠ .greedy)
    (h : execute fixed state .step = some (next, reply)) : next.random = fixed.nextRandom state.random := by
  simp only [execute] at h
  split at h
  next =>
    simp only [Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simp [selection, positive]
  next => simp at h

def run (fixed : FixedFunctions) (state : State) : List Command → Option (State × List Reply)
  | [] => some (state, [])
  | command :: commands =>
      match execute fixed state command with
      | none => none
      | some (next, reply) =>
          match run fixed next commands with
          | none => none
          | some (final, replies) => some (final, reply :: replies)

theorem run_preserves_wellFormed (fixed : FixedFunctions) (state final : State)
    (commands : List Command) (replies : List Reply) (wellFormed : state.WellFormed)
    (h : run fixed state commands = some (final, replies)) : final.WellFormed := by
  induction commands generalizing state final replies with
  | nil =>
      simp only [run, Option.some.injEq, Prod.mk.injEq] at h
      exact h.1 ▸ wellFormed
  | cons command commands ih =>
      cases hExecute : execute fixed state command with
      | none => simp [run, hExecute] at h
      | some result =>
          obtain ⟨next, reply⟩ := result
          cases hTail : run fixed next commands with
          | none => simp [run, hExecute, hTail] at h
          | some result =>
              obtain ⟨tail, tailReplies⟩ := result
              simp only [run, hExecute, hTail, Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact ih next tail tailReplies (execute_preserves_wellFormed fixed state next command reply hExecute) hTail

theorem run_reply_count (fixed : FixedFunctions) (state final : State)
    (commands : List Command) (replies : List Reply)
    (h : run fixed state commands = some (final, replies)) : replies.length = commands.length := by
  induction commands generalizing state final replies with
  | nil =>
      simp only [run, Option.some.injEq, Prod.mk.injEq] at h
      simp [h.2]
  | cons command commands ih =>
      cases hExecute : execute fixed state command with
      | none => simp [run, hExecute] at h
      | some result =>
          obtain ⟨next, reply⟩ := result
          cases hTail : run fixed next commands with
          | none => simp [run, hExecute, hTail] at h
          | some result =>
              obtain ⟨tail, tailReplies⟩ := result
              simp only [run, hExecute, hTail, Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              simp only [List.length_cons]
              exact congrArg Nat.succ (ih next tail tailReplies hTail)

theorem clear_same_settings (a b : State)
    (temperature : a.temperature = b.temperature) (seed : a.seed = b.seed) : cleared a = cleared b := by
  cases a
  cases b
  simp_all [cleared]

theorem clear_replay (fixed : FixedFunctions) (a b : State) (commands : List Command)
    (temperature : a.temperature = b.temperature) (seed : a.seed = b.seed) :
    run fixed (cleared a) commands = run fixed (cleared b) commands := by
  rw [clear_same_settings a b temperature seed]

end Board1.SeededPublicSurface
