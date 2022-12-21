open Utils

module Types : sig
  module type S = sig
    module Poly : sig
      module V2 : sig
        type ( 'ledger_hash
             , 'amount
             , 'pending_coinbase
             , 'fee_excess
             , 'sok_digest
             , 'local_state
             , 'bool )
             t =
          { source :
              ( 'ledger_hash
              , 'pending_coinbase
              , 'local_state )
              Mina_state_registers.V1.t
          ; target :
              ( 'ledger_hash
              , 'pending_coinbase
              , 'local_state )
              Mina_state_registers.V1.t
          ; connecting_ledger_left : 'ledger_hash
          ; connecting_ledger_right : 'ledger_hash
          ; supply_increase : 'amount
          ; fee_excess : 'fee_excess
          ; zkapp_updates_applied : 'bool
          ; sok_digest : 'sok_digest
          }
      end
    end

    module V2 : sig
      type t =
        ( Mina_base.Frozen_ledger_hash.V1.t
        , (Currency.Amount.V1.t, Sgn_type.Sgn.V1.t) Signed_poly.V1.t
        , Mina_base.Pending_coinbase.Stack_versioned.V1.t
        , Mina_base.Fee_excess.V1.t
        , unit
        , Mina_state_local_state.V1.t
        , bool )
        Poly.V2.t
    end

    module With_sok : sig
      module V2 : sig
        type t =
          ( Mina_base.Ledger_hash.V1.t
          , (Currency.Amount.V1.t, Sgn_type.Sgn.V1.t) Signed_poly.V1.t
          , Mina_base.Pending_coinbase.Stack_versioned.V1.t
          , Mina_base.Fee_excess.V1.t
          , Mina_base.Sok_message.Digest.V1.t
          , Mina_state_local_state.V1.t
          , bool )
          Poly.V2.t
      end
    end
  end
end

module type Concrete = sig
  module Poly : sig
    module V2 : sig
      type ( 'ledger_hash
           , 'amount
           , 'pending_coinbase
           , 'fee_excess
           , 'sok_digest
           , 'local_state
           , 'bool )
           t =
        { source :
            ( 'ledger_hash
            , 'pending_coinbase
            , 'local_state )
            Mina_state_registers.V1.t
        ; target :
            ( 'ledger_hash
            , 'pending_coinbase
            , 'local_state )
            Mina_state_registers.V1.t
        ; connecting_ledger_left : 'ledger_hash
        ; connecting_ledger_right : 'ledger_hash
        ; supply_increase : 'amount
        ; fee_excess : 'fee_excess
        ; zkapp_updates_applied : 'bool
        ; sok_digest : 'sok_digest
        }
    end
  end

  module V2 : sig
    type t =
      ( Mina_base.Frozen_ledger_hash.V1.t
      , (Currency.Amount.V1.t, Sgn_type.Sgn.V1.t) Signed_poly.V1.t
      , Mina_base.Pending_coinbase.Stack_versioned.V1.t
      , Mina_base.Fee_excess.V1.t
      , unit
      , Mina_state_local_state.V1.t
      , bool )
      Poly.V2.t
  end

  module With_sok : sig
    module V2 : sig
      type t =
        ( Mina_base.Ledger_hash.V1.t
        , (Currency.Amount.V1.t, Sgn_type.Sgn.V1.t) Signed_poly.V1.t
        , Mina_base.Pending_coinbase.Stack_versioned.V1.t
        , Mina_base.Fee_excess.V1.t
        , Mina_base.Sok_message.Digest.V1.t
        , Mina_state_local_state.V1.t
        , bool )
        Poly.V2.t
    end
  end
end

module M : Types.S

module type Local_sig = Signature(Types).S

module Make
    (Signature : Local_sig) (_ : functor (A : Concrete) -> Signature(A).S) :
  Signature(M).S

include
  Types.S
    with module Poly = M.Poly
     and module With_sok = M.With_sok
     and module V2 = M.V2
