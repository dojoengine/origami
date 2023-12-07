mod mocks {
    mod initializable_mock;
    mod erc20_allowance_mock;
    mod erc20_balance_mock;
    mod erc20_metadata_mock;
    mod erc20_mintable_burnable_mock;
}

mod security {
    #[cfg(test)]
    mod test_initializable;
}

mod token {
    #[cfg(test)]
    mod test_erc20_allowance;
    #[cfg(test)]
    mod test_erc20_balance;
    #[cfg(test)]
    mod test_erc20_metadata;
    #[cfg(test)]
    mod test_erc20_mintable_burnable;
}
