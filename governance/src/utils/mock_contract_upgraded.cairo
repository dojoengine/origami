use starknet::ContractAddress;

#[dojo::interface]
trait IHelloStarknetUgraded {
    fn increase_balance(amount: u128);
    fn decrease_balance(amount: u128);
    fn get_balance() -> u128;
}

#[derive(Model, Copy, Drop, Serde)]
struct MockBalances {
    #[key]
    account: u128,
    balance: u128,
}

#[dojo::contract]
mod hellostarknetupgraded {
    use super::{MockBalances, IHelloStarknetUgraded};

    #[abi(embed_v0)]
    impl HelloStarknetImpl of IHelloStarknetUgraded<ContractState> {
        // Increases the balance by the given amount.
        fn increase_balance(amount: u128) {
            let world = self.world_dispatcher.read();
            let curr_balance = get!(world, 1, MockBalances).balance;
            set!(world, MockBalances { account: 1, balance: curr_balance + amount });
        }

        // Decreases the balance by the given amount.
        fn decrease_balance(amount: u128) {
            let world = self.world_dispatcher.read();
            let curr_balance = get!(world, 1, MockBalances).balance;
            set!(world, MockBalances { account: 1, balance: curr_balance - amount });
        }

        // Gets the balance.
        fn get_balance() -> u128 {
            let world = self.world_dispatcher.read();
            get!(world, 1, MockBalances).balance
        }
    }
}
