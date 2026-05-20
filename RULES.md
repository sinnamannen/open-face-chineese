# OFC Pineapple Rules

This repository uses one locked ruleset as the engine source of truth.

## Variant

- Game: heads-up Open-Face Chinese Pineapple.
- Players: 2.
- Initial deal: each non-Fantasyland player receives 5 cards and places all 5.
- Pineapple turns: 4 turns of 3 cards. On each turn a non-Fantasyland player places 2 cards and discards 1.
- Final board: top 3 cards, middle 5 cards, bottom 5 cards.
- Board order: bottom must be at least as strong as middle, and middle must be at least as strong as top. Otherwise the board fouls.

## Fantasyland

- A clean final board enters Fantasyland when the top row contains QQ or better, including trips.
- Next-hand Fantasyland card counts:
  - QQ top: 14 cards.
  - KK top: 15 cards.
  - AA top: 16 cards.
  - Any top trips: 17 cards.
- A Fantasyland player sets a complete 13-card board and discards the extras.
- Re-Fantasyland requires a clean final board with at least one of:
  - trips on top,
  - full house or better in the middle,
  - quads or better on the bottom.
- If both players qualify, both receive Fantasyland on the next hand.

## Base Scoring

- Each line is worth 1 point.
- Winning all three lines earns a 3-point scoop bonus.
- A scoop is therefore worth 6 base points total.
- Tied lines score 0 for that line.
- If exactly one player fouls, the clean player wins 6 base points plus their own royalties. The fouled player earns no royalties.
- If both players foul, the hand scores 0.

## Royalties

Royalties apply even on losing lines when the board is clean.

### Top Row

| Hand | Points |
| --- | ---: |
| 66 | 1 |
| 77 | 2 |
| 88 | 3 |
| 99 | 4 |
| TT | 5 |
| JJ | 6 |
| QQ | 7 |
| KK | 8 |
| AA | 9 |
| 222 | 10 |
| 333 | 11 |
| 444 | 12 |
| 555 | 13 |
| 666 | 14 |
| 777 | 15 |
| 888 | 16 |
| 999 | 17 |
| TTT | 18 |
| JJJ | 19 |
| QQQ | 20 |
| KKK | 21 |
| AAA | 22 |

### Middle Row

| Hand | Points |
| --- | ---: |
| Trips | 2 |
| Straight | 4 |
| Flush | 8 |
| Full house | 12 |
| Quads | 20 |
| Straight flush | 30 |
| Royal flush | 50 |

### Bottom Row

| Hand | Points |
| --- | ---: |
| Straight | 2 |
| Flush | 4 |
| Full house | 6 |
| Quads | 10 |
| Straight flush | 15 |
| Royal flush | 25 |
