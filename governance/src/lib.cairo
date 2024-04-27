mod libraries {
    mod events;
    mod traits;
}

mod models {
    mod governor;
    mod timelock;
    mod token;
}

mod systems {
    mod governor {
        mod contract;
        mod interface;
        #[cfg(test)]
        mod tests;
    }
    mod timelock {
        mod contract;
        mod interface;
        #[cfg(test)]
        mod tests;
    }
    mod token {
        mod contract;
        mod interface;
        #[cfg(test)]
        mod tests;
    }
}

mod utils {
    mod mock_contract;
    mod mock_contract_upgraded;
    #[cfg(test)]
    mod testing;
}

