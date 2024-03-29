<!-- Your report starts here! -->

Lead Auditors:

- Stepan Popov

# Table of Contents

- [Table of Contents](#table-of-contents)
- [Protocol Summary](#protocol-summary)
- [Disclaimer](#disclaimer)
- [Risk Classification](#risk-classification)
- [Audit Details](#audit-details)
  - [Scope](#scope)
- [Executive Summary](#executive-summary)
  - [Issues found](#issues-found)
- [Findings](#findings)
- [High](#high)
- [Medium](#medium)
- [Low](#low)
- [Informational](#informational)
- [Gas](#gas)

# Protocol Summary

Protocol does X, Y, Z

# Disclaimer

I make all effort to find as many vulnerabilities in the code in the given time period, but holds no responsibilities for the findings provided in this document. A security audit by me is not an endorsement of the underlying business or product. The audit was time-boxed and the review of the code was solely on the security aspects of the Solidity implementation of the contracts.

# Risk Classification

|            |        | Impact |        |     |
| ---------- | ------ | ------ | ------ | --- |
|            |        | High   | Medium | Low |
|            | High   | H      | H/M    | M   |
| Likelihood | Medium | H/M    | M      | M/L |
|            | Low    | M      | M/L    | L   |

We use the [CodeHawks](https://docs.codehawks.com/hawks-auditors/how-to-evaluate-a-finding-severity) severity matrix to determine severity. See the documentation for more details.

All vulnerabilities discovered during the audit are classified based on their potential severity and have the following classification:

| Severity | Description                                                                                                                                                                                                                |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| High     | Bugs leading to assets theft, fund access locking, or any other loss of funds and bugs that can trigger a contract failure. Further recovery is possible only by manual modification of the contract state or replacement. |
| Medium   | Bugs that can break the intended contract logic or expose it to DoS attacks, but do not cause direct loss funds.                                                                                                           |
| Low      | Bugs that do not have a significant immediate impact and could be easily fixed.                                                                                                                                            |
| Gas      | Bugs that are tied to unnecessary wasted gas.                                                                                                                                                                              |

# Audit Details

## Scope

- KittenRaffle.sol

# Executive Summary

## Issues found

| Severity | # of Findings |
| -------- | ------------- |
| CRITICAL |       2        |
| HIGH     |       3        |
| MEDIUM   |               |
| LOW      |       1        |

# Findings

### Predictability of random of winner and rarity

#### Level

HIGH

#### Description

`block.difficulty` changes rarely, `msg.sender` might be generated specifically for wanted result for given `block.timestamp`.

For rarity random there are no even `block.timestamp`, so we can know exactly what rarity will be.

#### Recommendation

Use more complex random generator, f.e. use [VRF](https://coincodecap.com/how-to-generate-random-numbers-on-ethereum-using-vrf).

### Reentrancy in winner.call

#### Level

CRITICAL

#### Description

If caller of selectWinner is winner, then it can reenter this function and steal all eths on contract and generate many NFT's.

Moreover, the hacker can create 4 contracts within a transaction, create new game, and call selectWinner from winner contract (he knows who winner because the random is insecure).

Moreover, using with refund allows attacker to increase `players.length` and make it real to 100% win for desired player. (enterRaffle + refund).

#### Recommendation

Use safe transfer function instead of .call.

### Overflow in selectWinner

#### Level

CRITICAL

#### Description

```
uint256 totalAmountCollected = players.length * entranceFee
```

Can lead to overflow, so contract admin can steal players' money unfairly.

#### Recommendation

Use safe math.

### Less than 4 players using refund

#### Level

HIGH

#### Description

Players can use `refund` function to refund their money, but `players.length` remains unchanged.

#### Recommendation

Consider to iterate over players to check real player's addresses or remove this function. It can lead also to burning eths if winner player is `address(0)`.

### Less than 4 players using refund

#### Level

HIGH

#### Description

Players can use `refund` function to refund their money, but `players.length` remains unchanged.

#### Recommendation

Consider to iterate over players to check real player's addresses or remove this function.

### No need to store mappings

#### Level

GAS

#### Description

This contract doesn't have logic to add more rarities and cat types, so there is no need to store 

```
mapping(uint256 => string) public rarityToUri;
mapping(uint256 => string) public rarityToName;
```

#### Recommendation

Hardcode this in functions, do not use storage variables.
