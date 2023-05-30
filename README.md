# Introduction

A time-boxed security review of the **Whitelight** NFT Contracts was led by **Charlie Benson** of **0xThirdEye**, with a focus on the security aspects of the application's implementation, not gas optimizations.

# Disclaimer

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource and expertise-bound effort where I try to find as many vulnerabilities as possible. I can not guarantee 100% security after the review or even if the review will find any problems with your smart contracts. Subsequent security reviews, bug bounty programs and on-chain monitoring are strongly recommended.

# About **0xThirdEye**

**0xThirdEye**, is a team of smart contract security researchers. Working together privately and as participants of public audit contests, to contribute to the blockchain ecosystem and its protocols by putting time and effort into security research & reviews. Reach out on Twitter [@0xThirdEye](https://twitter.com/0xthirdeye)

# About **WhitelightNFT**

"White Light NFT is the exclusive launchpad partner for the World’s Finest NFT Artists and Animators."

This audit covered the ERC721A smart contract used by the team for their NFT collections. At the time of the audit, the contract managed the minting remuneration and withdrawals as well as the minting logic.

## Observations

This smart contract is an NFT collection based on the ERC721A architecture and standard - by [**AZUKI**](https://github.com/chiru-labs/ERC721A).

The contract implements the standard provided by the `ERC721AQueryable` extension, paired with the `BaseTokenURI` library from [**Divergencetech**](https://github.com/divergencetech/ethier/blob/main/contracts/erc721/BaseTokenURI.sol)

Overriding:

- `_startTokenId()` == 1, aligning with their use of the **HashLips** metadata engine.

- `_baseURI()` to set `BaseTokenURI._baseURI()` for `ERC721A`

- `tokenURI()` to prepare the URI JSON file names. Using `Strings` library from [**OpenZeppelin**](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol) `ECDSA`

The contract manages the shared withdrawal of funds between two addresses.
The withdrawal function can only be called by the contract owner.

The withdrawal calculated the amount of each of the `distributionAddress`'s relative to the `totalCollectedFunds`.

The `_withdraw` transfers the calculated amount to the relevant address, protected by the reentrancy guard and correct "Checks, Affects, Interactions" transfer pattern (assuming distribution addresses are known and not `address(0)`).

# Threat Model

`WhitelightNFT`:

- Unprivileged users can only call the `mint`, `getAvailableAmount`, `tokenURI` functions.
- Privileged users can call `withdraw`, `configure` and `set` Mint & Dist Addresses.

## Privileged Roles & Actors

- Owner - access to all privileged functions. Can be renounced and transferred.

## Security Interview

**Q:** What in the protocol has value in the market?

**A:** The ETH held within the smart contract and the NFTs minted to the user's wallets.

**Q:** In what case can the protocol/users lose money?

**A:** If funds/tokens are stuck/stolen from the smart contract or user wallets.

**Q:** What are some ways that an attacker achieves his goals?

**A:** TBC -- funds can become stuck in the contract in its current state.

# Severity classification

| Severity               | Impact: High | Impact: Medium | Impact: Low |
| ---------------------- | ------------ | -------------- | ----------- |
| **Likelihood: High**   | Critical     | High           | Medium      |
| **Likelihood: Medium** | High         | Medium         | Low         |
| **Likelihood: Low**    | Medium       | Low            | Low         |

**Impact** - the technical, economic and reputation damage of a successful attack

**Likelihood** - the chance that a particular vulnerability gets discovered and exploited

**Severity** - the overall criticality of the risk

# Security Assessment Summary

**_review commit hash_ - [d8907ce9c90f3caebe490feb8003ba6865e01a04](https://github.com/CharlieJRBenson/2023-05-whitelight-audit/commit/d8907ce9c90f3caebe490feb8003ba6865e01a04)**

**_fixes review commit hash_ - [TBD](https://github.com/CharlieJRBenson/2023-05-whitelight-audit/)**

### Scope

The following smart contracts were in the scope of the audit:

- `WhitelightNFT`
  - `erc721a/contracts/extensions/ERC721AQueryable.sol`
  - `@divergencetech/ethier/contracts/erc721/BaseTokenURI.sol`
  - `@openzeppelin/contracts/utils/cryptography/ECDSA.sol`
  - `@openzeppelin/contracts/security/ReentrancyGuard.sol`

The following number of issues were found, categorized by their severity:

- Critical & High: 1 issue
- Medium: 1 issue
- Low: 3 issues

---

# Findings Summary

| ID     | Title                                                              | Severity |
| ------ | ------------------------------------------------------------------ | -------- |
| [H-01] | Any smart contract funds "not-from-minting" will be locked forever | High     |
|        |                                                                    |          |
| [M-01] | Lack of 0 address checks for distribution addresses                | Medium   |
| [L-01] | Floating Pragma                                                    | Low      |
| [L-02] | Limited precision                                                  | Low      |
| [L-03] | Inappropriate function return/checks                               | Low      |

# Detailed Findings

# [H-01] Any smart contract funds "not-from-minting" will be locked forever

## Severity

**Impact:**
Medium, as "not-from-minting" funds are excess payments and failed function-sig calls (with message value). Only withdrawal addresses 1 & 2 are affected as the funds belong to them.

**Likelihood:**
High, any excess value sent to the mint function will be irretrievable. Any funds sent to the contract with a "non-minting" function signature will be irretrievable.

## Description

A variable `totalCollectedFunds` stores the gross total collected from minting cost. This is used to divide and manage the smart contracts fund withdrawals in the function `getAvailableAmount()`:

```solidity
function getAvailableAmount(
        address _address
    ) public view returns (uint256) {
        uint256 percentage = _address == distribution1address
            ? distribution1Percentage
            : distribution2Percentage;
        uint256 ownedAmount = (totalCollectedFunds * percentage) /
            FEE_DENOMINATOR;
        uint256 availableAmount = ownedAmount - withdrewAmount[_address];
        return availableAmount;
    }
```

Only funds recorded by the variable `totalCollectedFunds` can be withdrawn.

Upon receiving excess payment, the Mint function attempts to refund the excess to the user. This refund can fail if the user is a smart contract without a `receive()` function. Upon failing, these excess funds are irretrievable.

Upon receiving funds without a function signature, the `receive()` function is triggered, but does not record the funds to `totalCollectedFunds`, and therefore in this context is a futile function.

## Recommendations

It is not recommended to use the contract balance in the function `getAvailableAmount()` as that would introduce new risks such as erroneous accounting between the withdrawal addresses' shares of the funds.

The `totalCollectedFunds` should continue to be used however it should be handled in these edge cases.
E.g. upon failed refund of the excess minting costs, it should aggregate this value to `totalCollectedFunds`.
The same should be done within the `receive()` function.

## Discussion

**Charlie Benson:** Fixed.

# [M-01] Lack of 0 address checks for distribution addresses

## Severity

**Impact:**
High, large ETH balances can be sent and lost forever.

**Likelihood:**
Low, as it requires `address(0)` to be mistakenly configured as a distribution address.

## Description

`address(0)` can be mistakenly added as a distribution address if the `configure()` function is called incorrectly. The setters never check to prevent this.

When withdrawing, the entire balance owed to either `distributionAddress` 1 or 2 will be sent to `address(0)` and lost forever.

## Recommendations

Add a require statement checking against `address(0)` in the setter functions.

## Discussion

**Charlie Benson:** Fixed.

# [L-01] Floating Pragma

The solidity compiler version should be fixed to avoid possible compiler errors in the future.

## Discussion

**Charlie Benson:** Fixed.

# [L-02] Limited Precision

Possibility for small division errors / erroneous accounting using `FEE_DENOMINATOR` == 1000.
Very low impact as error rounds only small value differences between distribution addresses.

## Discussion

**Charlie Benson:** Acknowledged.

# [L-03] Inappropriate function return/checks

`getAvailableAmount()` is public and will return the `availableAmount` for `distributionAddress2` regardless of the input parameter (when it != `distributionAddress1`).

This misleads users to be told they have access to and are owed the balance of `distributionAddress2`.

## Recommendations

Can't change visibility as it is helpful for the project to check owed balances. Can instead check the parameter address is one of the distribution addresses only.

## Discussion

**Charlie Benson:** Acknowledged.
