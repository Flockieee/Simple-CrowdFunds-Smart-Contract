// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title CrowdFunds
 * @notice A simple crowdfunding smart contract that supports:
 *         - ETH funding
 *         - A single proposal
 *         - Yes/No voting system
 *         - Vote finalization
 *         - Conditional refunds
 *         - Owner withdrawal after approval and goal completion
 *
 * @dev
 *  - Implements CEI (Checks-Effects-Interactions) pattern
 *  - Includes a lightweight custom reentrancy guard
 *  - Voting follows 1 address = 1 vote (non-weighted)
 *  - Proposal struct contains an internal mapping and cannot be returned entirely
 */

contract CrowdFunds {
    // -------------------------
    // STORAGE
    // -------------------------

    /// @notice Amount of ETH contributed by each address, stored in wei
    mapping(address => uint256) public contributors;

    /// @notice Owner of the crowdfunding campaign (immutable)
    address public immutable owner;

    /// @notice Minimum allowed funding per transaction (in wei)
    uint256 public minimumFundInWei;

    /// @dev Reentrancy guard flag
    bool private locked;

    /**
     * @notice Representation of a single proposal for the crowdfunding campaign
     * @dev
     *  - voted mapping tracks whether an address has already voted
     *  - Cannot be returned directly due to containing a mapping
     */

    struct Proposal {
        string description;
        uint256 voteYes;
        uint256 voteNo;
        bool executed; // finalized flag
        bool approved;
        bool declined;
        uint256 goal; // in wei
        uint256 deadline; // unix timestamp
        mapping(address => bool) voted;
    }

    Proposal private proposal; // single proposal

    // -------------------------
    // EVENTS
    // -------------------------

    /// @notice Emitted whenever a user contributes ETH
    event Funded(address indexed user, uint256 amount);

    /// @notice Emitted whenever a user successfully claims a refund
    event Refunded(address indexed user, uint256 amount);

    /// @notice Emitted when the owner withdraws all funds
    event WithdrawAll(address indexed owner, uint256 amount);

    /// @notice Emitted when a user casts a vote
    event Voted(address indexed voter, bool support);

    /// @notice Emitted when the voting result is finalized
    event Finalized(bool approved, uint256 yes, uint256 no);

    // -------------------------
    // ERRORS
    // -------------------------

    error FUNDING_CLOSED();
    error ACCESS_DENIED();
    error FORBIDDEN();
    error INVALID_ADDRESS();
    error FUND_TOO_LOW(uint256 amount);
    error INSUFFICIENT_BALANCE(uint256 amount, uint256 balance);
    error WITHDRAW_FAILED();
    error INVALID_INPUT(uint256 balance);
    error STILL_IN_FUNDING_PERIOD();
    error ALREADY_FINALIZED();
    error YOURE_ALREADY_VOTE();
    error PROPOSAL_NOT_APPROVED();
    error GOAL_NOT_REACHED();
    error PROPOSAL_HAS_APPROVED();
    error PROPOSAL_IS_STILL_PENDING();
    error PROPOSAL_NOT_FINALIZED();
    error CONTRACT_INSUFFICIENT_BALANCE(uint256 requested, uint256 available);

    // -------------------------
    // MODIFIERS
    // -------------------------

    /// @notice Ensures that funding actions can only occur while the campaign is active
    modifier onlyWhileFunding() {
        if (block.timestamp >= proposal.deadline) revert FUNDING_CLOSED();
        _;
    }

    /// @notice Restricts access to the contract owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert ACCESS_DENIED();
        _;
    }

    /// @notice Prevents reentrant calls using a simple lock mechanism
    modifier antiReentrant() {
        if (locked == true) revert FORBIDDEN();
        locked = true;
        _;
        locked = false;
    }

    /// @notice Restricts function calls to addresses that have contributed
    modifier onlyContributor() {
        if (contributors[msg.sender] == 0) revert ACCESS_DENIED();
        _;
    }

    // -------------------------
    // CONSTRUCTOR
    // -------------------------

    /**
     * @notice Initializes the crowdfunding campaign
     * @param _goal Required funding target in wei
     * @param _owner Campaign owner
     * @param _description Description of the proposal
     * @param _durationSeconds Duration of the funding period in seconds
     * @param _minimumFundInWei Minimum ETH amount required per contribution
     *
     * @dev The proposal's deadline is calculated relative to the deployment timestamp
     */
    constructor(
        uint256 _goal,
        address _owner,
        string memory _description,
        uint256 _durationSeconds,
        uint256 _minimumFundInWei
    ) {
        if (_owner == address(0)) revert INVALID_ADDRESS();
        if (_durationSeconds == 0) revert INVALID_INPUT(0);

        owner = _owner;
        minimumFundInWei = _minimumFundInWei;
        locked = false;

        // init proposal
        proposal.goal = _goal;
        proposal.description = _description;
        proposal.deadline = block.timestamp + _durationSeconds;
    }

    // -------------------------
    // VIEWS
    // -------------------------

    /// @notice Overall campaign status
    enum Status {
        Active,
        Ended
    }

    /**
     * @notice Returns the current status of the crowdfunding campaign
     */
    function getStatus() public view returns (Status) {
        if (block.timestamp < proposal.deadline) return Status.Active;
        return Status.Ended;
    }

    /**
     * @notice Returns the current ETH balance of the contract
     */
    function getCurrentAmount() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Returns public information about the proposal
     */
    function proposalInfo()
        external
        view
        returns (
            uint256 goal,
            string memory description,
            uint256 yes,
            uint256 no,
            bool executed,
            bool approved,
            bool declined,
            uint256 deadline
        )
    {
        goal = proposal.goal; // @return goal Funding target in wei
        description = proposal.description; // @return description Text description of the proposal
        yes = proposal.voteYes; // @return yes Total yes votes
        no = proposal.voteNo; //  @return no Total no votes
        executed = proposal.executed; // @return executed Whether the vote has been finalized
        approved = proposal.approved; // @return approved Whether the proposal passed
        declined = proposal.declined; //  @return declined Whether the proposal was rejected
        deadline = proposal.deadline; // @return deadline UNIX timestamp when funding ends
    }

    // -------------------------
    // FUNDING
    // -------------------------

    /**
     * @notice Contribute ETH to the campaign
     * @dev Reverts if the contribution is below the minimum requirement
     */
    function fundEth() external payable onlyWhileFunding {
        if (msg.value < minimumFundInWei) revert FUND_TOO_LOW(msg.value);

        contributors[msg.sender] += msg.value;
        emit Funded(msg.sender, msg.value);
    }

    /**
     * @notice Receive ETH sent directly via transfer/send/call
     * @dev Acts the same as fundEth()
     */
    receive() external payable onlyWhileFunding {
        if (msg.value < minimumFundInWei) revert FUND_TOO_LOW(msg.value);

        contributors[msg.sender] += msg.value;
        emit Funded(msg.sender, msg.value);
    }

    // -------------------------
    // VOTING
    // -------------------------

    /**
     * @notice Cast a vote for the proposal (yes/no)
     * @param _voteYes true to vote yes, false to vote no
     *
     * @dev
     *  - Only contributors may vote
     *  - Voting is allowed only during the funding period
     *  - Each address may vote only once
     */
    function voting(bool _voteYes) external onlyContributor onlyWhileFunding {
        Proposal storage prop = proposal;
        if (prop.voted[msg.sender]) revert YOURE_ALREADY_VOTE();
        if (prop.executed) revert ALREADY_FINALIZED();

        // mark voted
        prop.voted[msg.sender] = true;

        // Weight decision: simple 1 address = 1 vote
        if (_voteYes) {
            prop.voteYes += 1;
        } else {
            prop.voteNo += 1;
        }
        emit Voted(msg.sender, _voteYes);
    }

    /**
     * @notice Finalizes the vote after the funding period ends
     * @dev
     *  - Uses simple majority (voteYes > voteNo)
     *  - Can only be executed once
     */
    function finalizeVote() external {
        Proposal storage prop = proposal;
        if (block.timestamp < prop.deadline) {
            revert STILL_IN_FUNDING_PERIOD();
        }
        if (prop.executed) revert ALREADY_FINALIZED();

        prop.executed = true;
        // simple majority by count of votes (not weighted)
        if (prop.voteYes > prop.voteNo) {
            prop.approved = true;
            prop.declined = false;
        } else {
            prop.approved = false;
            prop.declined = true;
        }

        emit Finalized(prop.approved, prop.voteYes, prop.voteNo);
    }

    // -------------------------
    // REFUND
    // -------------------------

    /**
     * @notice Claim a refund if the proposal is rejected OR the funding goal is not reached
     * @param _amountEthInWei The amount (in wei) to withdraw as refund
     *
     * @dev
     *  - Only contributors with sufficient balance may call
     *  - Refunds are only available after vote finalization
     *  - Refunds are not allowed if:
     *      (proposal is approved AND funding goal is achieved)
     *  - Protected by anti-reentrancy
     */
    function refund(uint256 _amountEthInWei) external antiReentrant {
        Proposal storage prop = proposal;
        if (_amountEthInWei == 0) {
            revert INVALID_INPUT(_amountEthInWei);
        }

        if (contributors[msg.sender] < _amountEthInWei) {
            revert INSUFFICIENT_BALANCE(_amountEthInWei, contributors[msg.sender]);
        }
        if (!prop.executed) revert PROPOSAL_NOT_FINALIZED();

        // If approved AND goal reach -> cannot refund
        if (prop.approved && address(this).balance >= prop.goal) {
            revert PROPOSAL_HAS_APPROVED();
        }

        if (address(this).balance < _amountEthInWei) {
            revert CONTRACT_INSUFFICIENT_BALANCE(_amountEthInWei, address(this).balance);
        }

        // CEI
        contributors[msg.sender] -= _amountEthInWei;

        (bool success,) = payable(msg.sender).call{value: _amountEthInWei}("");
        if (!success) revert WITHDRAW_FAILED();

        emit Refunded(msg.sender, _amountEthInWei);
    }

    // -------------------------
    // OWNER WITHDRAW
    // -------------------------

    /**
     * @notice Allows the owner to withdraw all contract funds if:
     *         - The vote has been finalized
     *         - The proposal is approved
     *         - The funding goal has been reached
     *
     * @dev Protected by the anti-reentrancy guard
     */
    function withdrawAllBalance() external onlyOwner antiReentrant {
        uint256 amount = address(this).balance;
        Proposal storage prop = proposal;
        if (!prop.executed) revert PROPOSAL_NOT_FINALIZED();
        if (amount < prop.goal) revert GOAL_NOT_REACHED();

        if (!prop.approved) revert PROPOSAL_NOT_APPROVED();

        // CEI not necessary for contract-level balance transfer, but keep pattern
        (bool success,) = payable(owner).call{value: amount}("");
        if (!success) revert WITHDRAW_FAILED();

        emit WithdrawAll(owner, amount);
    }

    // -------------------------
    // ADMIN / HELPER
    // -------------------------

    /**
     * @notice Allows the owner to update the minimum contribution amount
     * @param _minimumInWei New minimum contribution in wei
     *
     * @dev Can only be changed while funding is active
     */
    function setMinimumFund(uint256 _minimumInWei) external onlyOwner {
        if (block.timestamp >= proposal.deadline) revert FUNDING_CLOSED();
        minimumFundInWei = _minimumInWei;
    }

    // -------------------------
    // FALLBACK
    // -------------------------

    /**
     * @notice Reverts when calling a non-existent function
     */
    fallback() external {
        revert("Use receive() or valid function");
    }
}
