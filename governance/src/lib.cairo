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

