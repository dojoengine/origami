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

#[cfg(test)]
mod tests {
    mod constants;
    mod utils;
}
