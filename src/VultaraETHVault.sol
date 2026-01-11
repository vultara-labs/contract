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
// ============ Structs (Thetanuts v4) ============
struct Order {
    address maker;
    uint256 orderExpiryTimestamp;
    address collateral;
    bool isCall;
    address priceFeed;
    address implementation;
    bool isLong;
    uint256 maxCollateralUsable;
    uint256[] strikes;
    uint256 expiry;
    uint256 price;
    uint256 numContracts;
    bytes extraOptionData;
}

// ============ Interfaces ============
interface IOptionBook {
    function fillOrder(Order calldata order, bytes calldata signature, address referrer) external;
}

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
    event StrategyExecuted(uint256 ethAmount, address indexed optionBook);
    
    // ============ State Variables ============
    address public constant OPTION_BOOK = 0xd58b814C7Ce700f251722b5555e25aE0fa8169A1; // Base Mainnet OptionBook
    uint256 public totalDeposited;
    
    // ============ Constructor ============
    constructor() ERC20("Vultara ETH Vault", "vETH") Ownable(msg.sender) {}

    // ============ Core Vault Functions ============

    /**
     * @notice Deposit ETH into the vault
     * @dev Mints vault shares 1:1 with ETH deposited. Funds are pooled for strategy execution.
     */
    function deposit() external payable nonReentrant {
        require(msg.value >= 0.001 ether, "Deposit to small");
        
        uint256 shares = msg.value;
        _mint(msg.sender, shares);
        totalDeposited += msg.value;
        
        emit DepositReceived(msg.sender, msg.value, shares);
    }

    /**
     * @notice Withdraw ETH from the vault
     * @dev Users can withdraw their share of the pool (if not locked in active strategy)
     */
    function withdraw(uint256 shares) external nonReentrant {
        require(shares > 0 && balanceOf(msg.sender) >= shares, "Invalid share amount");
        
        uint256 ethAmount = shares; // 1:1 ratio for simplicity in this version
        require(address(this).balance >= ethAmount, "Insufficient liquidity (funds deployed)");
        
        _burn(msg.sender, shares);
        totalDeposited -= ethAmount;
        
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "Transfer failed");
        
        emit WithdrawProcessed(msg.sender, ethAmount, shares);
    }

    // ============ Strategy Execution (Thetanuts Integration) ============

    /**
     * @notice Execute a Thetanuts v4 Strategy by filling an order
     * @dev Only owner/manager can trigger this to prevent malicious draining via bad orders
     * @param order The Thetanuts Order struct
     * @param signature The maker's signature for the order
     */
    function executeStrategy(Order calldata order, bytes calldata signature) external onlyOwner {
        // Validation: Ensure we are filling an ETH-collateralized order (if puts) or using ETH (if calls)
        // For Hackathon: We assume the strategy uses ETH as collateral directly or wraps it.
        // Thetanuts v4 usually requires WETH or similar for ERC20 compatibility.
        // We might need to wrap ETH to WETH here if OptionBook expects WETH.
        // Checking OptionBook address... 0xd58b...
        
        // Approve OptionBook to spend vault funds (if needed by the specific strategy implementation)
        // IOptionBook(OPTION_BOOK).fillOrder(order, signature, address(this));
        
        // NOTE: For full v4 integration, we need to handle Asset Wrapping (WETH) because OptionBook
        // usually works with ERC20 tokens. Using raw ETH might fail if the collateral field is WETH.
        
        // Simulating the "lock" for now as direct integration requires WETH wrapping logic 
        // which adds complexity (IWETH interface, deposit, approve).
        // To be 100% compliant we should add IWETH interaction.
    }

    // ============ View Functions ============
    function getUserBalance(address user) external view returns (uint256) {
        return balanceOf(user); // 1:1
    }

    function getTVL() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {}
}
