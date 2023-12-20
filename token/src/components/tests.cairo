mod mocks {
    mod initializable_mock;
    mod src5_mock;
   
    mod erc20 {
        mod erc20_allowance_mock;
        mod erc20_balance_mock;
        mod erc20_metadata_mock;
        mod erc20_mintable_burnable_mock;
        mod erc20_bridgeable_mock;
    }
    
}

mod introspection {
    #[cfg(test)]
    mod test_src5;
}

mod security {
    #[cfg(test)]
    mod test_initializable;
}


mod token {
    mod erc20 {
        #[cfg(test)]
        mod test_erc20_allowance;
        #[cfg(test)]
        mod test_erc20_balance;
        #[cfg(test)]
        mod test_erc20_metadata;
        #[cfg(test)]
        mod test_erc20_mintable_burnable;
        #[cfg(test)]
        mod test_erc20_bridgeable;
    }

    mod erc711{

    }
}
