use governance::models::governor::Support;
use starknet::{ClassHash, ContractAddress, class_hash_const, contract_address_const};

impl ContractAddressDefault of Default<ContractAddress> {
    #[inline(always)]
    fn default() -> ContractAddress nopanic {
        contract_address_const::<0>()
    }
}

impl ClassHashDefault of Default<ClassHash> {
    #[inline(always)]
    fn default() -> ClassHash nopanic {
        class_hash_const::<0>()
    }
}

impl SupportDefault of Default<Support> {
    #[inline(always)]
    fn default() -> Support nopanic {
        Support::Abstain(())
    }
}
