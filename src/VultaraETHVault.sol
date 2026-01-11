// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VultaraETHVault
 * @notice ETH Vault for Vultara Protocol on Base
 * @dev Accepts native ETH deposits and issues vault shares (vETH).
 *      Simplified version for hackathon demo.
 */
contract VultaraETHVault is ERC20, Ownable, ReentrancyGuard {
    
    // ============ Events ============
    event DepositReceived(address indexed user, uint256 ethAmount, uint256 shares);
    event WithdrawProcessed(address indexed user, uint256 ethAmount, uint256 shares);
    event StrategyUpdated(address indexed newStrategy);

    // ============ State Variables ============
    address public strategyAddress;
    uint256 public totalDeposited;
    uint256 public performanceFee; // In basis points (e.g., 1000 = 10%)
    uint256 public constant MAX_FEE = 2000; // Max 20%
    uint256 public constant MIN_DEPOSIT = 0.001 ether; // Min 0.001 ETH

    // ============ Constructor ============
    constructor() ERC20("Vultara ETH Vault", "vETH") Ownable(msg.sender) {
        performanceFee = 1000; // Default 10%
    }

    // ============ Core Vault Functions ============

    /**
     * @notice Deposit ETH into the vault
     * @dev Mints vault shares 1:1 with ETH deposited
     */
    function deposit() external payable nonReentrant {
        require(msg.value >= MIN_DEPOSIT, "VultaraETHVault: deposit too small");
        
        uint256 shares = msg.value; // 1:1 for simplicity
        _mint(msg.sender, shares);
        totalDeposited += msg.value;
        
        emit DepositReceived(msg.sender, msg.value, shares);
    }

    /**
     * @notice Withdraw ETH from the vault
     * @param shares Amount of vault shares to burn
     */
    function withdraw(uint256 shares) external nonReentrant {
        require(shares > 0, "VultaraETHVault: shares must be > 0");
        require(balanceOf(msg.sender) >= shares, "VultaraETHVault: insufficient shares");
        
        uint256 ethAmount = convertToAssets(shares);
        require(address(this).balance >= ethAmount, "VultaraETHVault: insufficient vault balance");
        
        _burn(msg.sender, shares);
        totalDeposited -= ethAmount;
        
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "VultaraETHVault: ETH transfer failed");
        
        emit WithdrawProcessed(msg.sender, ethAmount, shares);
    }

    // ============ View Functions ============

    /**
     * @notice Get user's current vault balance in ETH equivalent
     * @param user Address to check
     * @return ETH value of user's shares
     */
    function getUserBalance(address user) external view returns (uint256) {
        return convertToAssets(balanceOf(user));
    }

    /**
     * @notice Convert shares to ETH amount
     * @param shares Amount of shares
     * @return ETH equivalent
     */
    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares; // 1:1 for simplicity
    }

    /**
     * @notice Convert ETH amount to shares
     * @param assets Amount of ETH
     * @return Shares equivalent
     */
    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets; // 1:1 for simplicity
    }

    /**
     * @notice Get total value locked in the vault
     * @return Total ETH in vault
     */
    function getTVL() external view returns (uint256) {
        return address(this).balance;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the strategy address for future Thetanuts integration
     * @param _strategy Address of the strategy contract
     */
    function setStrategy(address _strategy) external onlyOwner {
        require(_strategy != address(0), "VultaraETHVault: invalid strategy");
        strategyAddress = _strategy;
        emit StrategyUpdated(_strategy);
    }

    /**
     * @notice Update the performance fee
     * @param _fee New fee in basis points
     */
    function setPerformanceFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "VultaraETHVault: fee too high");
        performanceFee = _fee;
    }

    /**
     * @notice Emergency withdraw ETH (owner only)
     * @param amount Amount of ETH to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "VultaraETHVault: insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "VultaraETHVault: transfer failed");
    }

    // ============ Receive ETH ============
    receive() external payable {
        // Allow direct ETH transfers (will be counted when deposit() is called)
    }
}
