# CrowdFunds Smart Contract

> **Educational Project**: Simple crowdfunding smart contract with voting system
> 
> **Learning Journey**: Built while studying Cyfrin Updraft courses. Test suite generated with AI assistance as I'm still learning testing methodologies.

## 📋 Overview

CrowdFunds is a simple crowdfunding smart contract that enables:
- ETH-based fundraising campaigns
- Yes/No voting system for proposals
- Automatic refunds if proposal is rejected or goal not reached
- Owner withdrawal when proposal is approved and goal is met

## 🎯 Learning Goals

This project was built to learn:
- ✅ Solidity fundamentals & syntax
- ✅ Smart contract architecture & design patterns
- ✅ Security patterns (CEI Pattern, Reentrancy Guard)
- ✅ Gas optimization techniques
- ✅ Custom errors & events
- ✅ Modifiers & access control
- 🔄 Foundry testing framework (with AI assistance)

**Course Source**: [Cyfrin Updraft](https://updraft.cyfrin.io/) - Learning Solidity & Smart Contract Development

## 🏗️ Contract Architecture

### Storage
```solidity
mapping(address => uint256) public contributors;  // Track contributions
address public immutable owner;                    // Campaign owner
uint256 public minimumFundInWei;                   // Minimum contribution amount
bool private locked;                               // Reentrancy guard flag
Proposal private proposal;                         // Campaign proposal data
```

### Key Features

#### 1. **Funding Phase**
- Users can contribute ETH until deadline is reached
- Configurable minimum contribution amount
- Support via `fundEth()` function or direct contract transfer

#### 2. **Voting System**
- 1 address = 1 vote (non-weighted voting)
- Contributors can vote Yes/No during funding period
- Each address can only vote once

#### 3. **Finalization**
- After deadline, anyone can finalize the vote
- Simple majority: `voteYes > voteNo` = approved

#### 4. **Refund Mechanism**
- Contributors can claim refunds if:
  - ✅ Proposal is declined (rejected by vote)
  - ✅ Goal not reached (approved but balance < goal)
- Contributors CANNOT refund if:
  - ❌ Proposal is approved AND goal is reached

#### 5. **Owner Withdrawal**
- Owner can withdraw all funds if:
  - ✅ Vote has been finalized
  - ✅ Proposal is approved
  - ✅ Funding goal is reached

## 🔐 Security Features
 
### 1. **CEI Pattern** (Checks-Effects-Interactions)
```solidity
// ✅ Good: Update state before external call
contributors[msg.sender] -= amount;
(bool success, ) = msg.sender.call{value: amount}("");
```

### 2. **Custom Reentrancy Guard**
```solidity
modifier antiReentrant() {
    if (locked) revert FORBIDDEN();
    locked = true;
    _;
    locked = false;
}
```

### 3. **Access Control Modifiers**
- `onlyOwner` - Restricts functions to campaign owner
- `onlyContributor` - Only addresses that have contributed
- `onlyWhileFunding` - Only during active campaign period

### 4. **Custom Errors** (Gas Efficient)
```solidity
error FUNDING_CLOSED();
error ACCESS_DENIED();
error INSUFFICIENT_BALANCE(uint256 amount, uint256 balance);
error CONTRACT_INSUFFICIENT_BALANCE(uint256 requested, uint256 available);
// ... and more
```

## 📊 Contract Functions

### Public/External Functions

| Function | Access | Description |
|----------|--------|-------------|
| `fundEth()` | Anyone | Contribute ETH to the campaign |
| `voting(bool)` | Contributors | Vote Yes/No on the proposal |
| `finalizeVote()` | Anyone | Finalize vote after deadline |
| `refund(uint256)` | Contributors | Claim refund (conditional) |
| `withdrawAllBalance()` | Owner | Withdraw all funds (conditional) |
| `setMinimumFund(uint256)` | Owner | Update minimum contribution |

### View Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `getStatus()` | Status | Returns Active or Ended |
| `getCurrentAmount()` | uint256 | Current contract balance |
| `proposalInfo()` | tuple | Complete proposal information |
| `contributors(address)` | uint256 | Contribution amount per address |

## 🎮 Usage Examples

### Scenario 1: Successful Campaign ✅
```
1. Deploy contract (goal: 10 ETH, duration: 7 days)
2. Alice contributes 4 ETH
3. Bob contributes 6 ETH
4. Total: 10 ETH (goal reached ✅)

Voting Phase:
5. Alice votes YES
6. Bob votes YES
7. Result: 2 YES, 0 NO

Finalization:
8. Anyone calls finalizeVote()
9. Proposal status = APPROVED ✅

Withdrawal:
10. Owner calls withdrawAllBalance()
11. Owner receives 10 ETH
12. Contributors CANNOT refund (proposal approved + goal reached)
```

### Scenario 2: Failed Campaign - Rejected ❌
```
1. Deploy contract (goal: 10 ETH, duration: 7 days)
2. Alice contributes 4 ETH
3. Bob contributes 6 ETH
4. Total: 10 ETH

Voting Phase:
5. Alice votes NO
6. Bob votes NO
7. Result: 0 YES, 2 NO

Finalization:
8. Anyone calls finalizeVote()
9. Proposal status = DECLINED ❌

Refund:
10. Alice calls refund(4 ether) ✅
11. Bob calls refund(6 ether) ✅
12. Owner CANNOT withdraw (proposal declined)
```

### Scenario 3: Failed Campaign - Goal Not Reached 📉
```
1. Deploy contract (goal: 10 ETH, duration: 7 days)
2. Alice contributes 3 ETH
3. Bob contributes 2 ETH
4. Total: 5 ETH (goal NOT reached ❌)

Voting Phase:
5. Alice votes YES
6. Bob votes YES
7. Result: 2 YES, 0 NO

Finalization:
8. Anyone calls finalizeVote()
9. Proposal status = APPROVED ✅ (but goal not reached)

Refund:
10. Alice calls refund(3 ether) ✅ (allowed because balance < goal)
11. Bob calls refund(2 ether) ✅
12. Owner CANNOT withdraw (goal not reached)
```

## 🧪 Testing

### Setup
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and install dependencies
git clone <your-repo>
cd crowdfunds
forge install foundry-rs/forge-std
```

### Run Tests
```bash
# Compile contract
forge build

# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Run specific test
forge test --match-test test_FundEth_Success

# Gas report
forge test --gas-report

# Coverage report
forge coverage
```

### Test Coverage

The test suite covers:
- ✅ Deployment & initialization (4 tests)
- ✅ Funding mechanics (9 tests)
- ✅ Voting system (6 tests)
- ✅ Vote finalization (4 tests)
- ✅ Refund logic (10 tests)
- ✅ Owner withdrawal (5 tests)
- ✅ Admin functions (3 tests)
- ✅ Security tests (reentrancy, edge cases) (4 tests)
- ✅ Fuzz testing (2 tests)

**Total: 47+ test cases**

> **Note**: Test suite was generated with AI assistance as part of my learning journey. My focus is on understanding contract logic and security patterns. I'm still learning testing best practices through Cyfrin Updraft courses.

## 🔍 Key Learnings from Cyfrin Updraft

### 1. **State Management**
Learned how to properly manage state using mappings and structs, including handling mappings inside structs.

### 2. **Security-First Approach**
Implementing CEI pattern and reentrancy guards to prevent common attack vectors, following Cyfrin's security guidelines.

### 3. **Gas Optimization**
Applied optimization techniques:
- Using `immutable` for variables set in constructor
- Custom errors instead of require strings (saves ~20-30 gas per revert)
- Caching storage reads in memory

### 4. **Edge Case Handling**
The contract handles various edge cases:
- Refund after owner withdrawal (critical bug fixed!)
- Voting during/after deadline
- Multiple contributions from the same address
- Proper finalization state management

### 5. **Critical Bug Discovery & Fix**
Found and fixed a critical bug in the refund logic during code review:

```solidity
// ❌ BEFORE: State could be corrupted
contributors[msg.sender] -= amount;
(bool success, ) = msg.sender.call{value: amount}("");
if (!success) revert WITHDRAW_FAILED(); // Too late! State already changed!

// ✅ AFTER: Check contract balance BEFORE state changes
if (address(this).balance < _amountEthInWei) {
    revert CONTRACT_INSUFFICIENT_BALANCE(_amountEthInWei, address(this).balance);
}
contributors[msg.sender] -= _amountEthInWei; // Safe to update state now
(bool success, ) = msg.sender.call{value: _amountEthInWei}("");
if (!success) revert WITHDRAW_FAILED();
```

**The Bug**: If owner withdrew all funds, contributors could still call refund, which would update their balance in storage but fail to send ETH. This would result in permanent loss of contribution tracking.

**The Fix**: Added explicit check for contract balance before updating state, following CEI pattern strictly.

## 📚 Tech Stack

- **Language**: Solidity ^0.8.18
- **Framework**: Foundry (forge, cast, anvil)
- **Testing**: Forge test framework
- **Learning Platform**: [Cyfrin Updraft](https://updraft.cyfrin.io/)
- **Tools**: 
  - VSCode with Solidity extension
  - Foundry for compilation & testing
  - AI assistance for test generation

## ⚠️ Disclaimer

**FOR EDUCATIONAL PURPOSES ONLY**

This contract was built as a learning project while studying Cyfrin Updraft courses. It has NOT been audited and should **NOT** be used in production or on mainnet.

If you want to use similar code in production:
1. ✅ Get professional security audit
2. ✅ Extensive testing on testnets
3. ✅ Review all security best practices
4. ✅ Consider upgradability patterns
5. ✅ Add comprehensive access controls
6. ✅ Implement emergency pause mechanisms

## 🚀 Future Improvements

Possible enhancements for continued learning:
- [ ] Weighted voting based on contribution amount
- [ ] Support for multiple concurrent proposals
- [ ] ERC20 token support (not just ETH)
- [ ] Milestone-based fund releases
- [ ] Reward system for proposal creators
- [ ] Delegated voting mechanism
- [ ] Emergency pause functionality
- [ ] Upgradeable proxy pattern (UUPS/Transparent)

## 📖 Learning Resources

Resources used during this learning journey:
- [Cyfrin Updraft](https://updraft.cyfrin.io/) - Primary learning platform
- [Solidity Documentation](https://docs.soliditylang.org/)
- [Foundry Book](https://book.getfoundry.sh/)
- [Smart Contract Security Best Practices](https://consensys.github.io/smart-contract-best-practices/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)

## 🤝 Acknowledgments

- **Patrick Collins** and the Cyfrin team for amazing educational content
- Foundry team for excellent development tools
- AI assistance for test suite generation
- Solidity community for resources and best practices

## 📝 License

MIT License - Free to use for educational purposes

---

**Learning Status**: ✅ 1 Month into Solidity (via Cyfrin Updraft)

**Next Steps**: 
- Complete advanced Cyfrin courses
- Learn comprehensive testing patterns
- Study upgradeable contract architectures
- Explore DeFi protocol designs
- Practice more complex smart contract patterns

---

Built with 💙 while learning from [Cyfrin Updraft](https://updraft.cyfrin.io/)