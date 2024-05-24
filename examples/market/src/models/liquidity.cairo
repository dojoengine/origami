// Starknet imports

use starknet::ContractAddress;

// Dojo imports

use dojo::database::introspect::{Struct, Ty, Introspect, Member, Layout};

// External imports

use cubit::f128::types::fixed::Fixed;

// Constants

const SCALING_FACTOR: u128 = 10000;

impl IntrospectFixed of Introspect<Fixed> {
    #[inline(always)]
    fn size() -> Option<usize> {
        Option::Some(2)
    }

    #[inline(always)]
    fn layout() -> Layout {
        // layout.append(128);
        // layout.append(1);
        Layout::Fixed(array![128, 1].span())
    }

    #[inline(always)]
    fn ty() -> Ty {
        Ty::Struct(
            Struct {
                name: 'Fixed',
                attrs: array![].span(),
                children: array![
                    Member { name: 'mag', attrs: array![].span(), ty: Ty::Primitive('u128') },
                    Member { name: 'sign', attrs: array![].span(), ty: Ty::Primitive('bool') },
                ]
                    .span()
            }
        )
    }
}


#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct Liquidity {
    #[key]
    player: ContractAddress,
    #[key]
    item_id: u32,
    shares: Fixed,
}
