mod models {
    mod cash;
    mod item;
    mod liquidity;
    mod market;
}

mod systems {
    mod liquidity;
    mod trade;
}

#[cfg(test)]
mod tests {
    mod setup;
    mod trade;
}
