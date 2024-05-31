mod components {
    mod introspection {
        mod src5;
    }

    mod security {
        mod initializable;
    }

    mod token {
        mod erc20 {
            mod erc20_allowance;
            mod erc20_balance;
            mod erc20_bridgeable;
            mod erc20_burnable;
            mod erc20_metadata;
            mod erc20_mintable;
        }

        mod erc721 {
            mod erc721_approval;
            mod erc721_balance;
            mod erc721_burnable;
            mod erc721_enumerable;
            mod erc721_metadata;
            mod erc721_mintable;
            mod erc721_owner;
            mod erc721_receiver;
            mod interface;
        }
    }

    mod tests;
}

mod presets {
    mod erc20 {
        mod bridgeable;
        #[cfg(test)]
        mod tests_bridgeable;
    }

    mod erc721 {
        mod mintable_burnable;
        #[cfg(test)]
        mod tests_mintable_burnable;
    }
}

#[cfg(test)]
mod tests {
    mod constants;
    mod utils;
}
