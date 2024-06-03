mod constants;
mod store;

mod models {
    mod league;
    mod player;
    mod registry;
    mod slot;
}

mod systems {
    mod maker;
}

mod helpers {
    mod bitmap;
}

#[cfg(test)]
mod tests {
    mod setup;
    mod test_create;
    mod test_subscribe;
    mod test_unsubscribe;
    mod test_fight;
}
