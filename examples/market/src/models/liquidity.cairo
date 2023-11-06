// Starknet imports

use starknet::ContractAddress;

// Dojo imports

use dojo::database::schema::{Struct, Ty, SchemaIntrospection, Member, serialize_member};

// External imports

use cubit::f128::types::fixed::Fixed;

// Constants

const SCALING_FACTOR: u128 = 10000;

impl SchemaIntrospectionFixed of SchemaIntrospection<Fixed> {
    #[inline(always)]
    fn size() -> usize {
        2
    }

    #[inline(always)]
    fn layout(ref layout: Array<u8>) {
        layout.append(128);
        layout.append(1);
    }

    #[inline(always)]
    fn ty() -> Ty {
        Ty::Struct(
            Struct {
                name: 'Fixed',
                attrs: array![].span(),
                children: array![
                    serialize_member(
                        @Member { name: 'mag', ty: Ty::Primitive('u128'), attrs: array![].span() }
                    ),
                    serialize_member(
                        @Member { name: 'sign', ty: Ty::Primitive('bool'), attrs: array![].span() }
                    )
                ]
                    .span()
            }
        )
    }
}

#[derive(Model, Copy, Drop, Serde)]
struct Liquidity {
    #[key]
    player: ContractAddress,
    #[key]
    item_id: u32,
    shares: Fixed,
}
