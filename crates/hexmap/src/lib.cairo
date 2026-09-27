pub mod map;

pub mod types {
    pub mod direction;
}

pub mod finders {
    pub mod astar;
    pub mod bfs;
    pub mod dial;
    pub mod heap;
}

pub mod generators {
    pub mod caver;
    pub mod digger;
    pub mod mazer;
    pub mod spreader;
    pub mod walker;
}

pub mod helpers {
    pub mod asserter;
    pub mod bits;
    pub mod geometry;
    pub mod layout;

    #[cfg(target: "test")]
    pub mod printer;
    pub mod rng;
}

#[cfg(target: "test")]
pub mod tests {
    pub mod bench_astar;
    pub mod bench_bfs;
    pub mod bench_caver;
    pub mod bench_dial;
    pub mod bench_foundation;
    pub mod bench_map;
    pub mod bench_mazer;
    pub mod bench_spreader;
    pub mod bench_walker;
    pub mod fixtures;
    pub mod properties;
    pub mod variants;
}
