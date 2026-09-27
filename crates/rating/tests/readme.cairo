//! The examples of `README.md`, compiled against the public API.

use origami_rating::elo::EloTrait;

#[test]
fn test_readme_elo() {
    // Calculate rating change for player A
    let (change, is_negative) = EloTrait::rating_change(
        1200_u64, // Player A's current rating
        1400_u64, // Player B's current rating
        100_u16, // Outcome (100 = win, 50 = draw, 0 = loss)
        20_u8 // K-factor
    );
    // Apply the rating change
    let new_rating_a = if is_negative {
        1200 - change
    } else {
        1200 + change
    };
    println!("Player A's new rating: {}", new_rating_a);
    assert!(new_rating_a == 1215);
}
