/-
  Transition.lean — the WORM ledger transition, formalized.

  The ledger advances by appending blocks. A block is admissible
  against the current tail when (a) it names the current tail
  seal as its prev_hash — the chain cannot fork — and (b) its
  energy does not exceed the expected ceiling: the Frustration
  Hamiltonian descends, never climbs.

  The seal hash itself is a parameter here (core Lean has no
  SHA-256): every theorem is proved for an arbitrary seal
  function, so nothing in this file assumes collision resistance
  as a theorem. The concrete SHA-256 lives in the Rust runtime,
  the Erlang verifier, and the C node, byte-identical.

  The energy ceiling travels the C ABI as an unsigned 64-bit
  bound: energies are non-negative, so the signed int64 the C
  node decodes maps losslessly (the node refuses negative
  ceilings before calling, which the predicate would too —
  no non-negative energy descends to a negative bound).

  Energy order: energies in this system are non-negative f32
  values, and for non-negative floats the IEEE bit pattern
  ordered as UInt32 coincides with the float order — so the
  ceiling compares bit patterns directly.
-/

namespace Worm

/-- The fields of a block the transition predicate reads. -/
structure Block where
  prevHash   : List UInt8
  energyBits : UInt32
deriving DecidableEq

/-- The admissibility predicate: chain link + energy descent. -/
def admissible (expectedTail : List UInt8) (energyCeiling : Nat) (b : Block) : Bool :=
  decide (b.prevHash = expectedTail) &&
  decide (UInt32.toNat b.energyBits ≤ energyCeiling)

/-- An admissible block names the current tail: no forks. -/
theorem admissible_prev {t : List UInt8} {c : Nat} {b : Block}
    (h : admissible t c b = true) : b.prevHash = t := by
  unfold admissible at h
  rw [Bool.and_eq_true] at h
  exact of_decide_eq_true h.1

/-- An admissible block respects the energy ceiling. -/
theorem admissible_energy {t : List UInt8} {c : Nat} {b : Block}
    (h : admissible t c b = true) :
    UInt32.toNat b.energyBits ≤ c := by
  unfold admissible at h
  rw [Bool.and_eq_true] at h
  exact of_decide_eq_true h.2

/-- The predicate is a function: one verdict per input. -/
theorem admissible_det {t : List UInt8} {c : Nat} {b : Block} {r₁ r₂ : Bool}
    (h₁ : admissible t c b = r₁) (h₂ : admissible t c b = r₂) : r₁ = r₂ := by
  rw [← h₁, ← h₂]

/-- A chain under an arbitrary seal function: each block's
    prev_hash is the seal of the block before it, starting from
    the genesis tail. -/
def chainValid (sealFn : Block → List UInt8) (tail : List UInt8) :
    List Block → Bool
  | [] => true
  | b :: rest => decide (b.prevHash = tail) && chainValid sealFn (sealFn b) rest

/-- Append-only prefix preservation: if a chain is valid, every
    prefix of it is valid. Sealing more blocks can never rewrite
    the part already sealed. -/
theorem chainValid_prefix {sealFn : Block → List UInt8} {tail : List UInt8}
    (l₁ l₂ : List Block) :
    chainValid sealFn tail (l₁ ++ l₂) = true → chainValid sealFn tail l₁ = true := by
  induction l₁ generalizing tail with
  | nil => intro _; rfl
  | cons b rest ih =>
      intro h
      simp only [List.cons_append, chainValid] at *
      rw [Bool.and_eq_true] at h ⊢
      exact ⟨h.1, ih h.2⟩

/-- Wire decoding for the export: the block is the 180-byte
    WormBlock — prev_hash at bytes 0..32, energy f32 bits
    little-endian at bytes 112..116. -/
def blockOfWire (w : ByteArray) : Block :=
  let d := w.data.toList
  let byte (i : Nat) : UInt32 := (d.getD i 0).toUInt32
  { prevHash := d.take 32
    energyBits := byte 112 + (byte 113 <<< 8) + (byte 114 <<< 16) + (byte 115 <<< 24) }

end Worm

/-- The C ABI export the verifier C node calls.
    Args: expected tail seal (32 bytes), energy ceiling,
    the 180-byte wire block. Returns 1 iff admissible.
    A wire block of any other size is refused. -/
@[export lean_verify_transition]
def leanVerifyTransition (expectedTail : @& ByteArray) (expectedEnergy : UInt64)
    (block : @& ByteArray) : UInt8 :=
  if block.size = 180 && Worm.admissible expectedTail.data.toList (UInt64.toNat expectedEnergy) (Worm.blockOfWire block)
  then 1 else 0
