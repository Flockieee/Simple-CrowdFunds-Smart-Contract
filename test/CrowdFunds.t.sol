// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/CrowdFunds.sol";

/**
 * @title CrowdFundsTest
 * @notice Comprehensive test suite for CrowdFunds contract
 * @dev Tests cover:
 *      - Deployment scenarios
 *      - Funding mechanics
 *      - Voting system
 *      - Refund logic
 *      - Owner withdrawal
 *      - Edge cases & security
 */
contract CrowdFundsTest is Test {
    CrowdFunds public crowdfund;
    
    // Test actors
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public whale = makeAddr("whale");
    
    // Campaign parameters
    uint256 constant GOAL = 10 ether;
    uint256 constant MIN_FUND = 0.01 ether;
    uint256 constant DURATION = 7 days;
    string constant DESCRIPTION = "Build a decentralized exchange";
    
    // Events to test
    event Funded(address indexed user, uint256 amount);
    event Refunded(address indexed user, uint256 amount);
    event WithdrawAll(address indexed owner, uint256 amount);
    event Voted(address indexed voter, bool support);
    event Finalized(bool approved, uint256 yes, uint256 no);
    
    function setUp() public {
        // Deploy contract
        vm.prank(owner);
        crowdfund = new CrowdFunds(
            GOAL,
            owner,
            DESCRIPTION,
            DURATION,
            MIN_FUND
        );
        
        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(whale, 100 ether);
    }
    
    // ============================================
    // DEPLOYMENT TESTS
    // ============================================
    
    function test_Deployment_Success() public {
        assertEq(crowdfund.owner(), owner);
        assertEq(crowdfund.minimumFundInWei(), MIN_FUND);
        assertEq(uint(crowdfund.getStatus()), uint(CrowdFunds.Status.Active));
    }
    
    function test_Deployment_RevertInvalidOwner() public {
        vm.expectRevert(CrowdFunds.INVALID_ADDRESS.selector);
        new CrowdFunds(GOAL, address(0), DESCRIPTION, DURATION, MIN_FUND);
    }
    
    function test_Deployment_RevertZeroDuration() public {
        vm.expectRevert(abi.encodeWithSelector(CrowdFunds.INVALID_INPUT.selector, 0));
        new CrowdFunds(GOAL, owner, DESCRIPTION, 0, MIN_FUND);
    }
    
    function test_ProposalInfo() public {
        (
            uint256 goal,
            string memory description,
            uint256 yes,
            uint256 no,
            bool executed,
            bool approved,
            bool declined,
            uint256 deadline
        ) = crowdfund.proposalInfo();
        
        assertEq(goal, GOAL);
        assertEq(description, DESCRIPTION);
        assertEq(yes, 0);
        assertEq(no, 0);
        assertEq(executed, false);
        assertEq(approved, false);
        assertEq(declined, false);
        assertGt(deadline, block.timestamp);
    }
    
    // ============================================
    // FUNDING TESTS
    // ============================================
    
    function test_FundEth_Success() public {
        uint256 fundAmount = 1 ether;
        
        vm.expectEmit(true, false, false, true);
        emit Funded(alice, fundAmount);
        
        vm.prank(alice);
        crowdfund.fundEth{value: fundAmount}();
        
        assertEq(crowdfund.contributors(alice), fundAmount);
        assertEq(crowdfund.getCurrentAmount(), fundAmount);
    }
    
    function test_FundEth_MultipleContributions() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(alice);
        crowdfund.fundEth{value: 2 ether}();
        
        assertEq(crowdfund.contributors(alice), 3 ether);
    }
    
    function test_FundEth_RevertBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(CrowdFunds.FUND_TOO_LOW.selector, 0.001 ether));
        
        vm.prank(alice);
        crowdfund.fundEth{value: 0.001 ether}();
    }
    
    function test_FundEth_RevertAfterDeadline() public {
        // Warp time past deadline
        vm.warp(block.timestamp + DURATION + 1);
        
        vm.expectRevert(CrowdFunds.FUNDING_CLOSED.selector);
        
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
    }
    
    function test_Receive_Success() public {
        uint256 fundAmount = 1 ether;
        
        vm.expectEmit(true, false, false, true);
        emit Funded(alice, fundAmount);
        
        vm.prank(alice);
        (bool success, ) = address(crowdfund).call{value: fundAmount}("");
        
        assertTrue(success);
        assertEq(crowdfund.contributors(alice), fundAmount);
    }
    
    function test_Receive_RevertBelowMinimum() public {
        vm.prank(alice);
        (bool success, ) = address(crowdfund).call{value: 0.001 ether}("");
        
        assertFalse(success);
    }
    
    function test_GetStatus_Active() public {
        assertEq(uint(crowdfund.getStatus()), uint(CrowdFunds.Status.Active));
    }
    
    function test_GetStatus_Ended() public {
        vm.warp(block.timestamp + DURATION + 1);
        assertEq(uint(crowdfund.getStatus()), uint(CrowdFunds.Status.Ended));
    }
    
    // ============================================
    // VOTING TESTS
    // ============================================
    
    function test_Voting_YesVote() public {
        // Alice funds first
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.expectEmit(true, false, false, true);
        emit Voted(alice, true);
        
        vm.prank(alice);
        crowdfund.voting(true);
        
        (, , uint256 yes, uint256 no, , , ,) = crowdfund.proposalInfo();
        assertEq(yes, 1);
        assertEq(no, 0);
    }
    
    function test_Voting_NoVote() public {
        vm.prank(bob);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.expectEmit(true, false, false, true);
        emit Voted(bob, false);
        
        vm.prank(bob);
        crowdfund.voting(false);
        
        (, , uint256 yes, uint256 no, , , ,) = crowdfund.proposalInfo();
        assertEq(yes, 0);
        assertEq(no, 1);
    }
    
    function test_Voting_RevertNonContributor() public {
        vm.expectRevert(CrowdFunds.ACCESS_DENIED.selector);
        
        vm.prank(charlie);
        crowdfund.voting(true);
    }
    
    function test_Voting_RevertDoubleVote() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(alice);
        crowdfund.voting(true);
        
        vm.expectRevert(CrowdFunds.YOURE_ALREADY_VOTE.selector);
        
        vm.prank(alice);
        crowdfund.voting(false);
    }
    
    function test_Voting_RevertAfterDeadline() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.warp(block.timestamp + DURATION + 1);
        
        vm.expectRevert(CrowdFunds.FUNDING_CLOSED.selector);
        
        vm.prank(alice);
        crowdfund.voting(true);
    }
    
    // ============================================
    // FINALIZE VOTE TESTS
    // ============================================
    
    function test_FinalizeVote_Approved() public {
        // 3 contributors vote yes, 1 votes no
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(bob);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(charlie);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(whale);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(alice);
        crowdfund.voting(true);
        
        vm.prank(bob);
        crowdfund.voting(true);
        
        vm.prank(charlie);
        crowdfund.voting(true);
        
        vm.prank(whale);
        crowdfund.voting(false);
        
        // Warp past deadline
        vm.warp(block.timestamp + DURATION + 1);
        
        vm.expectEmit(false, false, false, true);
        emit Finalized(true, 3, 1);
        
        crowdfund.finalizeVote();
        
        (, , , , bool executed, bool approved, bool declined,) = crowdfund.proposalInfo();
        assertTrue(executed);
        assertTrue(approved);
        assertFalse(declined);
    }
    
    function test_FinalizeVote_Declined() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(bob);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(alice);
        crowdfund.voting(true);
        
        vm.prank(bob);
        crowdfund.voting(false);
        
        vm.warp(block.timestamp + DURATION + 1);
        
        vm.expectEmit(false, false, false, true);
        emit Finalized(false, 1, 1);
        
        crowdfund.finalizeVote();
        
        (, , , , bool executed, bool approved, bool declined,) = crowdfund.proposalInfo();
        assertTrue(executed);
        assertFalse(approved);
        assertTrue(declined);
    }
    
    function test_FinalizeVote_RevertBeforeDeadline() public {
        vm.expectRevert(CrowdFunds.STILL_IN_FUNDING_PERIOD.selector);
        crowdfund.finalizeVote();
    }
    
    function test_FinalizeVote_RevertAlreadyFinalized() public {
        vm.warp(block.timestamp + DURATION + 1);
        
        crowdfund.finalizeVote();
        
        vm.expectRevert(CrowdFunds.ALREADY_FINALIZED.selector);
        crowdfund.finalizeVote();
    }
    
    // ============================================
    // REFUND TESTS
    // ============================================

     function test_Refund_RevertZeroAmount() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        vm.expectRevert(abi.encodeWithSelector(CrowdFunds.INVALID_INPUT.selector, 0 ether));
        
        vm.prank(alice);
        crowdfund.refund(0);
    }
    
    function test_Refund_ProposalDeclined() public {
        // Fund
        vm.prank(alice);
        crowdfund.fundEth{value: 2 ether}();
        
        vm.prank(bob);
        crowdfund.fundEth{value: 1 ether}();
        
        // Vote (bob votes no, alice doesn't vote - no wins)
        vm.prank(bob);
        crowdfund.voting(false);
        
        // Finalize
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        // Refund
        uint256 aliceBalBefore = alice.balance;
        
        vm.expectEmit(true, false, false, true);
        emit Refunded(alice, 2 ether);
        
        vm.prank(alice);
        crowdfund.refund(2 ether);
        
        assertEq(alice.balance, aliceBalBefore + 2 ether);
        assertEq(crowdfund.contributors(alice), 0);
    }
    
    function test_Refund_GoalNotReached() public {
        // Fund below goal
        vm.prank(alice);
        crowdfund.fundEth{value: 3 ether}();
        
        vm.prank(bob);
        crowdfund.fundEth{value: 2 ether}();
        
        // Vote yes
        vm.prank(alice);
        crowdfund.voting(true);
        
        vm.prank(bob);
        crowdfund.voting(true);
        
        // Finalize (approved but goal not reached)
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        // Should allow refund
        vm.prank(alice);
        crowdfund.refund(3 ether);
        
        assertEq(crowdfund.contributors(alice), 0);
    }
    
    function test_Refund_PartialAmount() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 5 ether}();
        
        vm.prank(bob);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(bob);
        crowdfund.voting(false);
        
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        // Partial refund
        vm.prank(alice);
        crowdfund.refund(2 ether);
        
        assertEq(crowdfund.contributors(alice), 3 ether);
        
        // Refund remaining
        vm.prank(alice);
        crowdfund.refund(3 ether);
        
        assertEq(crowdfund.contributors(alice), 0);
    }
    
    
    function test_Refund_RevertInsufficientBalance() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdFunds.INSUFFICIENT_BALANCE.selector,
                2 ether,
                1 ether
            )
        );
        
        vm.prank(alice);
        crowdfund.refund(2 ether);
    }
    
    function test_Refund_RevertNotFinalized() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.warp(block.timestamp + DURATION + 1);
        
        vm.expectRevert(CrowdFunds.PROPOSAL_NOT_FINALIZED.selector);
        
        vm.prank(alice);
        crowdfund.refund(1 ether);

    }
    
    function test_Refund_RevertProposalApprovedAndGoalReached() public {
        // Fund above goal
        vm.prank(alice);
        crowdfund.fundEth{value: 6 ether}();
        
        vm.prank(bob);
        crowdfund.fundEth{value: 5 ether}();
        
        // Vote yes
        vm.prank(alice);
        crowdfund.voting(true);
        
        vm.prank(bob);
        crowdfund.voting(true);
        
        // Finalize
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        // Should revert refund
        vm.expectRevert(CrowdFunds.PROPOSAL_HAS_APPROVED.selector);
        
        vm.prank(alice);
        crowdfund.refund(1 ether);
    }
    
    // ============================================
    // OWNER WITHDRAWAL TESTS
    // ============================================
    
    function test_WithdrawAllBalance_Success() public {
        // Fund above goal
        vm.prank(alice);
        crowdfund.fundEth{value: 6 ether}();
        
        vm.prank(bob);
        crowdfund.fundEth{value: 5 ether}();
        
        // Vote yes
        vm.prank(alice);
        crowdfund.voting(true);
        
        vm.prank(bob);
        crowdfund.voting(true);
        
        // Finalize
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        uint256 ownerBalBefore = owner.balance;
        uint256 contractBal = address(crowdfund).balance;
        
        vm.expectEmit(true, false, false, true);
        emit WithdrawAll(owner, contractBal);
        
        vm.prank(owner);
        crowdfund.withdrawAllBalance();
        
        assertEq(owner.balance, ownerBalBefore + contractBal);
        assertEq(address(crowdfund).balance, 0);
    }
    
    function test_WithdrawAllBalance_RevertNotOwner() public {
        vm.expectRevert(CrowdFunds.ACCESS_DENIED.selector);
        
        vm.prank(alice);
        crowdfund.withdrawAllBalance();
    }
    
    function test_WithdrawAllBalance_RevertNotFinalized() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 11 ether}();
        
        vm.warp(block.timestamp + DURATION + 1);
        
        vm.expectRevert(CrowdFunds.PROPOSAL_NOT_FINALIZED.selector);
        
        vm.prank(owner);
        crowdfund.withdrawAllBalance();
    }
    
    function test_WithdrawAllBalance_RevertGoalNotReached() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 5 ether}();
        
        vm.prank(alice);
        crowdfund.voting(true);
        
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        vm.expectRevert(CrowdFunds.GOAL_NOT_REACHED.selector);
        
        vm.prank(owner);
        crowdfund.withdrawAllBalance();
    }
    
    function test_WithdrawAllBalance_RevertNotApproved() public {
        vm.prank(alice);
        crowdfund.fundEth{value: 11 ether}();
        
        vm.prank(alice);
        crowdfund.voting(false);
        
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        vm.expectRevert(CrowdFunds.PROPOSAL_NOT_APPROVED.selector);
        
        vm.prank(owner);
        crowdfund.withdrawAllBalance();
    }
    
    // ============================================
    // ADMIN TESTS
    // ============================================
    
    function test_SetMinimumFund_Success() public {
        uint256 newMin = 0.1 ether;
        
        vm.prank(owner);
        crowdfund.setMinimumFund(newMin);
        
        assertEq(crowdfund.minimumFundInWei(), newMin);
    }
    
    function test_SetMinimumFund_RevertNotOwner() public {
        vm.expectRevert(CrowdFunds.ACCESS_DENIED.selector);
        
        vm.prank(alice);
        crowdfund.setMinimumFund(0.1 ether);
    }
    
    function test_SetMinimumFund_RevertAfterDeadline() public {
        vm.warp(block.timestamp + DURATION + 1);
        
        vm.expectRevert(CrowdFunds.FUNDING_CLOSED.selector);
        
        vm.prank(owner);
        crowdfund.setMinimumFund(0.1 ether);
    }
    
    // ============================================
    // EDGE CASES & SECURITY
    // ============================================
    
    function test_Reentrancy_RefundProtection() public {
        // Deploy attacker contract
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(crowdfund));
        vm.deal(address(attacker), 10 ether);
        
        // Fund via attacker (need to fund enough to trigger refund)
        vm.prank(address(attacker));
        crowdfund.fundEth{value: 2 ether}();
        
        // Add another contributor to vote no (so proposal gets declined)
        vm.prank(alice);
        crowdfund.fundEth{value: 1 ether}();
        
        vm.prank(alice);
        crowdfund.voting(false);
        
        // Finalize vote
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        // Try reentrancy attack via attacker contract
        // The attack will fail with FORBIDDEN because of reentrancy guard
        vm.expectRevert(CrowdFunds.WITHDRAW_FAILED.selector);
        vm.prank(address(attacker));
        attacker.claimRefund();
    }
    
    function test_Fallback_Revert() public {
        vm.prank(alice);
        (bool success, ) = address(crowdfund).call(
            abi.encodeWithSignature("nonExistentFunction()")
        );
        
        assertFalse(success);
    }
    
    function test_ComplexScenario_FullCycle() public {
        // Phase 1: Funding
        vm.prank(alice);
        crowdfund.fundEth{value: 4 ether}();
        
        vm.prank(bob);
        crowdfund.fundEth{value: 3 ether}();
        
        vm.prank(charlie);
        crowdfund.fundEth{value: 5 ether}();
        
        assertEq(crowdfund.getCurrentAmount(), 12 ether);
        
        // Phase 2: Voting
        vm.prank(alice);
        crowdfund.voting(true);
        
        vm.prank(bob);
        crowdfund.voting(true);
        
        vm.prank(charlie);
        crowdfund.voting(false);
        
        // Phase 3: Finalize (Yes wins 2-1)
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        (, , , , , bool approved, ,) = crowdfund.proposalInfo();
        assertTrue(approved);
        
        // Phase 4: Owner withdraws
        uint256 ownerBalBefore = owner.balance;
        
        vm.prank(owner);
        crowdfund.withdrawAllBalance();
        
        assertEq(owner.balance, ownerBalBefore + 12 ether);
        assertEq(address(crowdfund).balance, 0);
        
        // Phase 5: Contributors cannot refund after owner withdrew
        // After withdrawal, contract balance = 0
        // Should revert with CONTRACT_INSUFFICIENT_BALANCE
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdFunds.CONTRACT_INSUFFICIENT_BALANCE.selector,
                1 ether, // requested
                0        // available
            )
        );
        
        vm.prank(alice);
        crowdfund.refund(1 ether);
    }
    
    function testFuzz_Funding(uint96 amount) public {
        vm.assume(amount >= MIN_FUND && amount <= 100 ether);
        
        vm.prank(alice);
        crowdfund.fundEth{value: amount}();
        
        assertEq(crowdfund.contributors(alice), amount);
    }
    
    function testFuzz_Refund(uint96 fundAmount, uint96 refundAmount) public {
        vm.assume(fundAmount >= MIN_FUND && fundAmount <= 100 ether);
        vm.assume(refundAmount > 0 && refundAmount <= fundAmount);
        
        vm.prank(alice);
        crowdfund.fundEth{value: fundAmount}();
        
        vm.prank(bob);
        crowdfund.fundEth{value: MIN_FUND}();
        
        vm.prank(bob);
        crowdfund.voting(false);
        
        vm.warp(block.timestamp + DURATION + 1);
        crowdfund.finalizeVote();
        
        vm.prank(alice);
        crowdfund.refund(refundAmount);
        
        assertEq(crowdfund.contributors(alice), fundAmount - refundAmount);
    }
}

// ============================================
// MOCK ATTACKER CONTRACT FOR REENTRANCY TEST
// ============================================

contract ReentrancyAttacker {
    CrowdFunds public target;
    uint256 public attackCount;
    
    constructor(address _target) {
        target = CrowdFunds(payable(_target));
    }
    
    function claimRefund() external {
        attackCount = 0;
        target.refund(1 ether);
    }
    
    receive() external payable {
        // Try to re-enter once
        if (attackCount == 0 && address(target).balance >= 1 ether) {
            attackCount++;
            target.refund(1 ether); // This should revert with FORBIDDEN
        }
    }
}