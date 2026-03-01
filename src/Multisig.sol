// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Multisig
 * @notice 2-of-2 wallet for two parties: both must approve before any transfer.
 * Transfers native ETH or ERC20 from the contract to a recipient.
 */
contract Multisig {
    address[2] public owners;
    uint256 public nextTxId;

    struct Proposal {
        address target;
        uint256 value;
        bytes data;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public approvals;

    event Proposed(uint256 indexed txId, address indexed target, uint256 value, bytes data, address proposer);
    event Approved(uint256 indexed txId, address indexed owner);
    event Executed(uint256 indexed txId, address indexed target, uint256 value);

    error OnlyOwner();
    error InvalidTxId();
    error AlreadyExecuted();
    error NotFullyApproved();
    error InvalidTarget();
    error ExecutionFailed();

    modifier onlyOwner() {
        if (msg.sender != owners[0] && msg.sender != owners[1]) revert OnlyOwner();
        _;
    }

    constructor(address _owner0, address _owner1) {
        require(_owner0 != address(0) && _owner1 != address(0), "Invalid owner");
        require(_owner0 != _owner1, "Owners must differ");
        owners[0] = _owner0;
        owners[1] = _owner1;
        nextTxId = 1;
    }

    receive() external payable {}

    function _propose(address target, uint256 value, bytes memory data) internal returns (uint256 txId) {
        if (target == address(0)) revert InvalidTarget();
        txId = nextTxId++;
        proposals[txId] = Proposal({ target: target, value: value, data: data, executed: false });
        approvals[txId][msg.sender] = true;
        emit Proposed(txId, target, value, data, msg.sender);
        return txId;
    }

    /// @notice Propose sending ETH to a recipient. Proposer counts as first approval.
    function proposeNative(address to, uint256 value) external onlyOwner returns (uint256 txId) {
        return _propose(to, value, "");
    }

    /// @notice Propose sending ERC20 from this contract to a recipient. Proposer counts as first approval.
    function proposeERC20(address token, address to, uint256 amount) external onlyOwner returns (uint256 txId) {
        if (token == address(0) || to == address(0)) revert InvalidTarget();
        bytes memory callData = abi.encodeWithSignature("transfer(address,uint256)", to, amount);
        return _propose(token, 0, callData);
    }

    /// @notice Approve a proposal. Both owners must approve before execute.
    function approve(uint256 txId) external onlyOwner {
        if (txId >= nextTxId) revert InvalidTxId();
        Proposal storage p = proposals[txId];
        if (p.executed) revert AlreadyExecuted();
        approvals[txId][msg.sender] = true;
        emit Approved(txId, msg.sender);
    }

    /// @notice Execute a proposal. Requires both owners to have approved.
    function execute(uint256 txId) external onlyOwner {
        if (txId >= nextTxId) revert InvalidTxId();
        Proposal storage p = proposals[txId];
        if (p.executed) revert AlreadyExecuted();
        if (!approvals[txId][owners[0]] || !approvals[txId][owners[1]]) revert NotFullyApproved();

        p.executed = true;
        (bool success, ) = p.target.call{ value: p.value }(p.data);
        if (!success) revert ExecutionFailed();
        emit Executed(txId, p.target, p.value);
    }
}
