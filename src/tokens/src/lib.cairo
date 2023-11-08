mod erc721 {
    mod models;
    mod erc721;
    use erc721::ERC721;
    #[cfg(test)]
    mod tests;
}

#[cfg(test)]
mod tests {
    mod constants;
    mod utils;
}
