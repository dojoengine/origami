use starknet::ContractAddress;


#[derive(Copy, Drop, Serde, Introspect)]
pub enum DojoFrenKind {
    KatanaFren,
    SozoFren,
    ToriiFren,
}


#[derive(Copy, Drop, Serde)]
#[dojo::model]
pub struct DojoFren {
    #[key]
    player_id: ContractAddress,
    #[key]
    kind: DojoFrenKind,
    spawned: u32,
}


