// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VultaraVault
 * @notice ERC-4626 Vault for Vultara Protocol on Base
 * @dev Accepts USDC deposits and issues vault shares (vUSDC).
 *      Designed for integration with Thetanuts V4 options strategies.
 */
contract VultaraVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Events ============
    event DepositReceived(address indexed user, uint256 assets, uint256 shares);
    event WithdrawProcessed(address indexed user, uint256 assets, uint256 shares);
    event YieldClaimed(address indexed user, uint256 amount);
    event StrategyUpdated(address indexed newStrategy);

    // ============ State Variables ============
    address public strategyAddress; // Future: Thetanuts integration
    uint256 public totalYieldGenerated;
    uint256 public performanceFee; // In basis points (e.g., 1000 = 10%)
    uint256 public constant MAX_FEE = 2000; // Max 20%

    mapping(address => uint256) public userYieldClaimed;

    // ============ Constructor ============
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) Ownable(msg.sender) {
        performanceFee = 1000; // Default 10%
    }

    // ============ Core Vault Functions ============

    /**
     * @notice Deposit USDC into the vault
     * @param assets Amount of USDC to deposit
     * @param receiver Address to receive vault shares
     * @return shares Amount of vault shares minted
     */
    function deposit(uint256 assets, address receiver) 
        public 
        override 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(assets > 0, "VultaraVault: deposit amount must be > 0");
        
        shares = super.deposit(assets, receiver);
        
        emit DepositReceived(receiver, assets, shares);
        return shares;
    }

    /**
     * @notice Withdraw USDC from the vault
     * @param assets Amount of USDC to withdraw
     * @param receiver Address to receive USDC
     * @param owner Owner of the shares being burned
     * @return shares Amount of vault shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = super.withdraw(assets, receiver, owner);
        
        emit WithdrawProcessed(owner, assets, shares);
        return shares;
    }

    /**
     * @notice Redeem vault shares for USDC
     * @param shares Amount of vault shares to redeem
     * @param receiver Address to receive USDC
     * @param owner Owner of the shares being burned
     * @return assets Amount of USDC returned
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        assets = super.redeem(shares, receiver, owner);
        
        emit WithdrawProcessed(owner, assets, shares);
        return assets;
    }

    // ============ View Functions ============

    /**
     * @notice Get user's current vault balance in USDC equivalent
     * @param user Address to check
     * @return USDC value of user's shares
     */
    function getUserBalance(address user) external view returns (uint256) {
        return convertToAssets(balanceOf(user));
    }

    /**
     * @notice Get total value locked in the vault
     * @return Total USDC in vault
     */
    function getTVL() external view returns (uint256) {
        return totalAssets();
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the strategy address for future Thetanuts integration
     * @param _strategy Address of the strategy contract
     */
    function setStrategy(address _strategy) external onlyOwner {
        require(_strategy != address(0), "VultaraVault: invalid strategy");
        strategyAddress = _strategy;
        emit StrategyUpdated(_strategy);
    }

    /**
     * @notice Update the performance fee
     * @param _fee New fee in basis points
     */
    function setPerformanceFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "VultaraVault: fee too high");
        performanceFee = _fee;
    }

    /**
     * @notice Emergency withdraw (owner only)
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(IERC20 token, uint256 amount) external onlyOwner {
        token.safeTransfer(owner(), amount);
    }

    // ============ Internal Overrides ============

    /**
     * @dev Decimals offset for share calculation precision
     */
    function _decimalsOffset() internal pure override returns (uint8) {
        return 0;
    }
}
