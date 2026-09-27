//! The examples of `README.md`, compiled against the public API.

use origami_map::map::MapTrait;

const WIDTH: u8 = 18;
const HEIGHT: u8 = 14;
const ORDER: u8 = 0;
const SEED: felt252 = 'SEED';

#[test]
fn test_readme_maze() {
    let width = 18;
    let height = 14;
    let order = 0;
    let seed = 'SEED';
    let maze_map = MapTrait::new_maze(width, height, order, seed);
    assert!(maze_map.grid != 0);
}

#[test]
fn test_readme_cave() {
    let width = 18;
    let height = 14;
    let order = 3;
    let seed = 'SEED';
    let cave_map = MapTrait::new_cave(width, height, order, seed);
    // This seed yields an empty cave: the cellular automaton removes every tile
    assert!(cave_map.grid == 0);
}

#[test]
fn test_readme_random_walk() {
    let width = 18;
    let height = 14;
    let steps = 500;
    let seed = 'SEED';
    let random_walk_map = MapTrait::new_random_walk(width, height, steps, seed);
    assert!(random_walk_map.grid != 0);
}

#[test]
fn test_readme_open_with_corridor() {
    let (width, height, order, seed) = (WIDTH, HEIGHT, ORDER, SEED);
    let mut map = MapTrait::new_maze(width, height, order, seed);
    let position = 1;
    let order = 0;
    map.open_with_corridor(position, order);
}

#[test]
fn test_readme_open_with_maze() {
    let (width, height, order, seed) = (WIDTH, HEIGHT, ORDER, SEED);
    let mut map = MapTrait::new_maze(width, height, order, seed);
    let position = 1;
    let order = 0;
    map.open_with_maze(position, order);
}

#[test]
fn test_readme_search_path() {
    let (width, height, order, seed) = (WIDTH, HEIGHT, ORDER, SEED);
    let mut map = MapTrait::new_maze(width, height, order, seed);
    map.open_with_corridor(1, 0);
    let (start_position, end_position) = (1, 1 + 2 * WIDTH);
    // Empty when the target is a wall or unreachable
    let path = map.search_path(start_position, end_position);
    assert!(path.len() == 0);
}

#[test]
fn test_readme_compute_distribution() {
    let (width, height, order, seed) = (WIDTH, HEIGHT, ORDER, SEED);
    let map = MapTrait::new_maze(width, height, order, seed);
    let distribution = map.compute_distribution(10, seed);
    assert!(distribution != 0);
}
