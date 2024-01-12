// Dojo imports

use dojo::world::IWorldDispatcher;

trait ITrade<TContractState> {
    fn buy(self: @TContractState, world: IWorldDispatcher, item_id: u32, quantity: u128);
    fn sell(self: @TContractState, world: IWorldDispatcher, item_id: u32, quantity: u128);
}

#[dojo::contract]
mod Trade {
    // Internal imports

    use market::models::{item::Item, cash::Cash, market::{Market, MarketTrait}};

    // Local imports

    use super::ITrade;

    #[abi(embed_v0)]
    impl TradeImpl of ITrade<ContractState> {
        fn buy(self: @ContractState, world: IWorldDispatcher, item_id: u32, quantity: u128) {
            let player = starknet::get_caller_address();

            let player_cash = get!(world, (player), Cash);

            let market = get!(world, (item_id), Market);

            let cost = market.buy(quantity);
            assert(cost <= player_cash.amount, 'not enough cash');

            // update market
            set!(
                world,
                (Market {
                    item_id: item_id,
                    cash_amount: market.cash_amount + cost,
                    item_quantity: market.item_quantity - quantity,
                })
            );

            // update player cash
            set!(world, (Cash { player: player, amount: player_cash.amount - cost }));

            // update player item
            let item = get!(world, (player, item_id), Item);
            set!(
                world,
                (Item { player: player, item_id: item_id, quantity: item.quantity + quantity })
            );
        }


        fn sell(self: @ContractState, world: IWorldDispatcher, item_id: u32, quantity: u128) {
            let player = starknet::get_caller_address();

            let item = get!(world, (player, item_id), Item);
            let player_quantity = item.quantity;
            assert(player_quantity >= quantity, 'not enough items');

            let player_cash = get!(world, (player), Cash);

            let market = get!(world, (item_id), Market);
            let payout = market.sell(quantity);

            // update market
            set!(
                world,
                (Market {
                    item_id: item_id,
                    cash_amount: market.cash_amount - payout,
                    item_quantity: market.item_quantity + quantity,
                })
            );

            // update player cash
            set!(world, (Cash { player: player, amount: player_cash.amount + payout }));

            // update player item
            set!(
                world,
                (Item { player: player, item_id: item_id, quantity: player_quantity - quantity })
            );
        }
    }
}
