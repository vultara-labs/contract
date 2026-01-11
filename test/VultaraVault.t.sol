// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VultaraVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @notice Simple mock USDC for testing
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000 * 10**6); // 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract VultaraVaultTest is Test {
    VultaraVault public vault;
    MockUSDC public usdc;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public owner;
    
    uint256 constant INITIAL_BALANCE = 10_000 * 10**6; // 10,000 USDC

    function setUp() public {
        owner = address(this);
        
        // Deploy mock USDC
        usdc = new MockUSDC();
        
        // Deploy vault
        vault = new VultaraVault(
            IERC20(address(usdc)),
            "Vultara USDC Vault",
            "vUSDC"
        );
        
        // Fund test accounts
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
    }

    // ============ Deposit Tests ============

    function test_Deposit() public {
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC
        
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();
        
        assertGt(shares, 0, "Should receive shares");
        assertEq(vault.balanceOf(alice), shares, "Alice should have shares");
        assertEq(vault.getUserBalance(alice), depositAmount, "User balance should match deposit");
    }

    function test_DepositEmitsEvent() public {
        uint256 depositAmount = 500 * 10**6;
        
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        
        vm.expectEmit(true, false, false, true);
        emit VultaraVault.DepositReceived(alice, depositAmount, depositAmount);
        
        vault.deposit(depositAmount, alice);
        vm.stopPrank();
    }

    function test_DepositZeroReverts() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1);
        
        vm.expectRevert("VultaraVault: deposit amount must be > 0");
        vault.deposit(0, alice);
        vm.stopPrank();
    }

    // ============ Withdraw Tests ============

    function test_Withdraw() public {
        uint256 depositAmount = 1000 * 10**6;
        
        // Alice deposits
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        
        // Alice withdraws half
        uint256 withdrawAmount = 500 * 10**6;
        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(alice), INITIAL_BALANCE - depositAmount + withdrawAmount, "USDC balance should be correct");
    }

    function test_Redeem() public {
        uint256 depositAmount = 1000 * 10**6;
        
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        
        // Redeem all shares
        uint256 assets = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        
        assertEq(assets, depositAmount, "Should receive full deposit back");
        assertEq(vault.balanceOf(alice), 0, "Should have no shares left");
    }

    // ============ TVL Tests ============

    function test_TVL() public {
        assertEq(vault.getTVL(), 0, "TVL should start at 0");
        
        // Alice deposits
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000 * 10**6);
        vault.deposit(1000 * 10**6, alice);
        vm.stopPrank();
        
        // Bob deposits
        vm.startPrank(bob);
        usdc.approve(address(vault), 2000 * 10**6);
        vault.deposit(2000 * 10**6, bob);
        vm.stopPrank();
        
        assertEq(vault.getTVL(), 3000 * 10**6, "TVL should be 3000 USDC");
    }

    // ============ Admin Tests ============

    function test_SetStrategy() public {
        address newStrategy = address(0x123);
        
        vault.setStrategy(newStrategy);
        
        assertEq(vault.strategyAddress(), newStrategy, "Strategy should be set");
    }

    function test_SetStrategyNonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setStrategy(address(0x123));
    }

    function test_SetPerformanceFee() public {
        vault.setPerformanceFee(500); // 5%
        assertEq(vault.performanceFee(), 500, "Fee should be updated");
    }

    function test_SetPerformanceFeeTooHighReverts() public {
        vm.expectRevert("VultaraVault: fee too high");
        vault.setPerformanceFee(3000); // 30% > MAX_FEE
    }

    // ============ Edge Cases ============

    function test_MultipleDepositsAndWithdraws() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        
        // Multiple deposits
        vault.deposit(100 * 10**6, alice);
        vault.deposit(200 * 10**6, alice);
        vault.deposit(300 * 10**6, alice);
        
        assertEq(vault.getUserBalance(alice), 600 * 10**6, "Total balance should be 600 USDC");
        
        // Partial withdraw
        vault.withdraw(250 * 10**6, alice, alice);
        
        assertEq(vault.getUserBalance(alice), 350 * 10**6, "Remaining balance should be 350 USDC");
        vm.stopPrank();
    }
}
