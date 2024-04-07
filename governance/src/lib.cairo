mod libraries {
    mod events;
}

mod models {
    mod delegate;
    mod delegator;
    mod governor;
    mod timelock;
    mod token;
}

mod systems {
    mod delegate {
        mod contract;
        mod interface;
        mod tests;
    }
    mod delegator {
        mod contract;
        mod interface;
        mod tests;
    }
    mod governor {
        mod contract;
        mod interface;
        mod tests;
    }
    mod timelock {
        mod contract;
        mod interface;
        mod tests;
    }
    mod token {
        mod contract;
        mod interface;
        mod tests;
    }
}

