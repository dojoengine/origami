// Internal imports

use origami_pathfinding::helpers::heap::ItemTrait;

// Types.
#[derive(Copy, Drop)]
pub struct Node {
    pub index: u8,
    pub fcost: u16,
    pub hcost: u16,
}

/// Implementations.
#[generate_trait]
pub impl NodeImpl of NodeTrait {
    #[inline]
    fn new(fcost: u16, hcost: u16) -> Node {
        Node { index: 0, fcost: fcost, hcost: hcost }
    }
}

pub impl ItemImpl of ItemTrait<Node> {
    #[inline]
    fn get_index(self: Node) -> u8 {
        self.index
    }

    #[inline]
    fn set_index(ref self: Node, index: u8) {
        self.index = index;
    }
}

pub impl NodePartialOrd of PartialOrd<Node> {
    #[inline]
    fn lt(lhs: Node, rhs: Node) -> bool {
        if lhs.fcost == rhs.fcost {
            return lhs.hcost < rhs.hcost;
        }
        lhs.fcost < rhs.fcost
    }

    #[inline]
    fn le(lhs: Node, rhs: Node) -> bool {
        if lhs.fcost == rhs.fcost {
            return lhs.hcost <= rhs.hcost;
        }
        lhs.fcost <= rhs.fcost
    }

    #[inline]
    fn gt(lhs: Node, rhs: Node) -> bool {
        if lhs.fcost == rhs.fcost {
            return lhs.hcost > rhs.hcost;
        }
        lhs.fcost > rhs.fcost
    }

    #[inline]
    fn ge(lhs: Node, rhs: Node) -> bool {
        if lhs.fcost == rhs.fcost {
            return lhs.hcost >= rhs.hcost;
        }
        lhs.fcost >= rhs.fcost
    }
}
