# Map

The Origami Map crate is a library that provides map generation and manipulation functionalities for Dojo-based games. It offers efficient implementations of various map-related algorithms and data structures commonly used in game development.

## Overview

The Map crate focuses on providing tools for creating, manipulating, and navigating 2D grid-based maps. Its primary scope includes:

- Map generation algorithms (maze, cave, random walk)
- Pathfinding
- Object distribution on maps
- Hexagonal grid support

The crate is designed to work seamlessly with the Dojo engine and other Origami crates.

## Features

### Map Generation

- Maze generation using [Prim's algorithm](https://en.wikipedia.org/wiki/Prim%27s_algorithm)
- Cave generation using a [cellular automata-like](https://en.wikipedia.org/wiki/Cellular_automaton) approach
- [Random walk](https://en.wikipedia.org/wiki/Random_walk) map generation

### Pathfinding

- [A\* algorithm](https://en.wikipedia.org/wiki/A*_search_algorithm) for finding the shortest path between two points

### Map Manipulation

- Adding corridors to existing maps
- Integrating mazes into existing maps

### Object Distribution

- Spreading objects uniformly across walkable areas of the map

### Hexagonal Grid Support

- Basic operations for hexagonal grids

## Installation

To add the Origami Map crate as a dependency in your project, you need to modify your Scarb.toml file. Add the following to your [dependencies] section:

```toml
[dependencies]
origami_map = { git = "https://github.com/dojoengine/origami" }
```

Make sure you have dojo installed and configured in your project.

## How to use it?

Here are some examples of how to use the Map crate:

### Generating a maze

```rust
use origami_map::map::MapTrait;

let width = 18;
let height = 14;
let order = 0;
let seed = 'SEED';
let maze_map = MapTrait::new_maze(width, height, order, seed);
```

### Generating a cave

```rust
use origami_map::map::MapTrait;

let width = 18;
let height = 14;
let order = 3;
let seed = 'SEED';
let cave_map = MapTrait::new_cave(width, height, order, seed);
```

### Generating a random walk

```rust
use origami_map::map::MapTrait;

let width = 18;
let height = 14;
let steps = 500;
let seed = 'SEED';
let random_walk_map = MapTrait::new_random_walk(width, height, steps, seed);
```

### Opening an existing map with a corridor

```rust
use origami_map::map::MapTrait;

let mut map = MapTrait::new_maze(width, height, order, seed);
let position = 1;
let order = 0;
map.open_with_corridor(position, order);
```

### Opening an existing map with a maze

```rust
use origami_map::map::MapTrait;

let mut map = MapTrait::new_maze(width, height, order, seed);
let position = 1;
let order = 0;
map.open_with_maze(position, order);
```

### Finding a path using A\* algorithm

```rust
use origami_map::map::MapTrait;

let map = MapTrait::new_maze(width, height, order, seed);
let path = map.search_path(start_position, end_position);
```

### Distributing objects on the map

```rust
use origami_map::map::MapTrait;

let map = MapTrait::new_maze(width, height, order, seed);
let distribution = map.compute_distribution(10, seed);
```

Remember to import the necessary traits and types when using the Map crate in your project.
