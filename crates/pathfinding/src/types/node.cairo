// Internal imports

use origami_pathfinding::helpers::heap::ItemTrait;

// Types.
#[derive(Copy, Drop)]
pub struct Node {
    pub position: u8,
    pub source: u8,
    pub gcost: u16,
    pub hcost: u16,
}

/// Implementations.
#[generate_trait]
pub impl NodeImpl of NodeTrait {
    #[inline]
    fn new(position: u8, source: u8, gcost: u16, hcost: u16) -> Node {
        Node { position, source, gcost, hcost }
    }
}

pub impl ItemImpl of ItemTrait<Node> {
    #[inline]
    fn key(self: Node) -> u8 {
        self.position
    }
}

pub impl NodePartialEq of PartialEq<Node> {
    #[inline]
    fn eq(lhs: @Node, rhs: @Node) -> bool {
        lhs.position == rhs.position
    }

    #[inline]
    fn ne(lhs: @Node, rhs: @Node) -> bool {
        lhs.position != rhs.position
    }
}

pub impl NodePartialOrd of PartialOrd<Node> {
    #[inline]
    fn lt(lhs: Node, rhs: Node) -> bool {
        if lhs.gcost + lhs.hcost == rhs.gcost + rhs.hcost {
            return lhs.hcost < rhs.hcost;
        }
        lhs.gcost + lhs.hcost < rhs.gcost + rhs.hcost
    }

    #[inline]
    fn le(lhs: Node, rhs: Node) -> bool {
        if lhs.gcost + lhs.hcost == rhs.gcost + rhs.hcost {
            return lhs.hcost <= rhs.hcost;
        }
        lhs.gcost + lhs.hcost <= rhs.gcost + rhs.hcost
    }

    #[inline]
    fn gt(lhs: Node, rhs: Node) -> bool {
        if lhs.gcost + lhs.hcost == rhs.gcost + rhs.hcost {
            return lhs.hcost > rhs.hcost;
        }
        lhs.gcost + lhs.hcost > rhs.gcost + rhs.hcost
    }

    #[inline]
    fn ge(lhs: Node, rhs: Node) -> bool {
        if lhs.gcost + lhs.hcost == rhs.gcost + rhs.hcost {
            return lhs.hcost >= rhs.hcost;
        }
        lhs.gcost + lhs.hcost >= rhs.gcost + rhs.hcost
    }
}
