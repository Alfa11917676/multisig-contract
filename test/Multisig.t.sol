// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { Multisig } from "../src/Multisig.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;
    uint256 private _totalSupply;

    function mint(address to, uint256 amount) external {
        _balanceOf[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view returns (uint256) { return _balanceOf[account]; }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balanceOf[msg.sender] >= amount, "insufficient balance");
        _balanceOf[msg.sender] -= amount;
        _balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    function allowance(address, address) external pure returns (uint256) { return 0; }
    function approve(address, uint256) external pure returns (bool) { return true; }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balanceOf[from] >= amount, "insufficient balance");
        _balanceOf[from] -= amount;
        _balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
    function name() external pure returns (string memory) { return "Mock"; }
    function symbol() external pure returns (string memory) { return "MOCK"; }
    function decimals() external pure returns (uint8) { return 18; }
}

contract MultisigTest is Test {
    Multisig public multisig;
    MockERC20 public token;

    address public owner0;
    address public owner1;
    address public stranger;
    address public recipient;

    function setUp() public {
        owner0 = vm.addr(1);
        owner1 = vm.addr(2);
        stranger = vm.addr(3);
        recipient = vm.addr(4);
        multisig = new Multisig(owner0, owner1);
        token = new MockERC20();
    }

    // ---- Basic flow: propose -> approve by second -> execute ----
    function test_BasicFlow_NativeTransfer() public {
        vm.deal(address(multisig), 1 ether);
        vm.prank(owner0);
        uint256 txId = multisig.proposeNative(recipient, 0.5 ether);
        assertEq(txId, 1);
        assertTrue(multisig.approvals(1, owner0));
        assertFalse(multisig.approvals(1, owner1));

        vm.prank(owner0);
        vm.expectRevert(Multisig.NotFullyApproved.selector);
        multisig.execute(1);

        vm.prank(owner1);
        multisig.approve(1);

        uint256 balBefore = recipient.balance;
        vm.prank(owner1);
        multisig.execute(1);
        assertEq(recipient.balance, balBefore + 0.5 ether);
        assertEq(address(multisig).balance, 0.5 ether);
        (, , , bool executed) = multisig.proposals(1);
        assertTrue(executed);
    }

    function test_BasicFlow_ERC20Transfer() public {
        token.mint(address(multisig), 1000e18);
        vm.prank(owner0);
        uint256 txId = multisig.proposeERC20(address(token), recipient, 500e18);
        assertEq(txId, 1);

        vm.prank(owner1);
        multisig.approve(1);

        vm.prank(owner0);
        multisig.execute(1);
        assertEq(token.balanceOf(recipient), 500e18);
        assertEq(token.balanceOf(address(multisig)), 500e18);
    }

    // ---- Validation: only owners ----
    function test_RevertWhen_NonOwnerProposes() public {
        vm.prank(stranger);
        vm.expectRevert(Multisig.OnlyOwner.selector);
        multisig.proposeNative(recipient, 1 ether);
    }

    function test_RevertWhen_NonOwnerApproves() public {
        vm.deal(address(multisig), 1 ether);
        vm.prank(owner0);
        multisig.proposeNative(recipient, 0.5 ether);
        vm.prank(stranger);
        vm.expectRevert(Multisig.OnlyOwner.selector);
        multisig.approve(1);
    }

    function test_RevertWhen_NonOwnerExecutes() public {
        vm.deal(address(multisig), 1 ether);
        vm.prank(owner0);
        multisig.proposeNative(recipient, 0.5 ether);
        vm.prank(owner1);
        multisig.approve(1);
        vm.prank(stranger);
        vm.expectRevert(Multisig.OnlyOwner.selector);
        multisig.execute(1);
    }

    // ---- Double approve is idempotent ----
    function test_DoubleApprove_IsIdempotent() public {
        vm.deal(address(multisig), 1 ether);
        vm.prank(owner0);
        multisig.proposeNative(recipient, 0.5 ether);
        vm.prank(owner1);
        multisig.approve(1);
        vm.prank(owner1);
        multisig.approve(1); // no revert
        vm.prank(owner0);
        multisig.execute(1);
        assertEq(recipient.balance, 0.5 ether);
    }

    // ---- Execute without both approvals ----
    function test_RevertWhen_ExecuteWithoutBothApprovals() public {
        vm.deal(address(multisig), 1 ether);
        vm.prank(owner0);
        multisig.proposeNative(recipient, 0.5 ether);
        vm.prank(owner1);
        vm.expectRevert(Multisig.NotFullyApproved.selector);
        multisig.execute(1);
    }

    // ---- Execute twice ----
    function test_RevertWhen_ExecuteAlreadyExecuted() public {
        vm.deal(address(multisig), 1 ether);
        vm.prank(owner0);
        multisig.proposeNative(recipient, 0.5 ether);
        vm.prank(owner1);
        multisig.approve(1);
        vm.prank(owner0);
        multisig.execute(1);
        vm.prank(owner1);
        vm.expectRevert(Multisig.AlreadyExecuted.selector);
        multisig.execute(1);
    }

    // ---- Invalid txId (no proposals yet, nextTxId is 1 so txId 1 is invalid) ----
    function test_RevertWhen_ApproveInvalidTxId() public {
        vm.prank(owner0);
        vm.expectRevert(Multisig.InvalidTxId.selector);
        multisig.approve(1);
    }

    function test_RevertWhen_ExecuteInvalidTxId() public {
        vm.prank(owner0);
        vm.expectRevert(Multisig.InvalidTxId.selector);
        multisig.execute(1);
    }

    // ---- Fund transfer tests ----
    function test_TransferVariousAmounts_Native() public {
        vm.deal(address(multisig), 10 ether);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.5 ether;
        amounts[1] = 1 ether;
        amounts[2] = 2 ether;
        for (uint256 i = 0; i < amounts.length; i++) {
            vm.prank(owner0);
            uint256 txId = multisig.proposeNative(recipient, amounts[i]);
            vm.prank(owner1);
            multisig.approve(txId);
            vm.prank(owner0);
            multisig.execute(txId);
        }
        assertEq(recipient.balance, 3.5 ether);
        assertEq(address(multisig).balance, 6.5 ether);
    }

    function test_TransferEntireBalance_Native() public {
        vm.deal(address(multisig), 5 ether);
        vm.prank(owner0);
        uint256 txId = multisig.proposeNative(recipient, 5 ether);
        vm.prank(owner1);
        multisig.approve(txId);
        vm.prank(owner0);
        multisig.execute(txId);
        assertEq(recipient.balance, 5 ether);
        assertEq(address(multisig).balance, 0);
    }

    function test_ReceiveEth() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool sent,) = address(multisig).call{ value: 1 ether }("");
        assertTrue(sent);
        assertEq(address(multisig).balance, 1 ether);
    }

    // ---- Invalid target ----
    function test_RevertWhen_ProposeNativeToZero() public {
        vm.prank(owner0);
        vm.expectRevert(Multisig.InvalidTarget.selector);
        multisig.proposeNative(address(0), 1 ether);
    }

    function test_RevertWhen_ProposeERC20ZeroToken() public {
        vm.prank(owner0);
        vm.expectRevert(Multisig.InvalidTarget.selector);
        multisig.proposeERC20(address(0), recipient, 100);
    }

    function test_RevertWhen_ProposeERC20ZeroRecipient() public {
        vm.prank(owner0);
        vm.expectRevert(Multisig.InvalidTarget.selector);
        multisig.proposeERC20(address(token), address(0), 100);
    }
}
