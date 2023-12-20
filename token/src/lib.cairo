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

        }
    }

    mod tests;
}

mod erc20 {
    mod interface;
    mod models;
    mod erc20;
    use erc20::ERC20;
    #[cfg(test)]
    mod tests;
}

mod erc721 {
    mod interface;
    mod models;
    mod erc721;
    use erc721::ERC721;
    #[cfg(test)]
    mod tests;
}

mod erc1155 {
    mod interface;
    mod models;
    mod erc1155;
    use erc1155::ERC1155;
    #[cfg(test)]
    mod tests;
}

mod presets {
    mod erc20 {
        mod bridgeable;
        #[cfg(test)]
        mod tests_bridgeable;
    }
}

#[cfg(test)]
mod tests {
    mod constants;
    mod utils;
}
