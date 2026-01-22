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

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address guy, uint256 wad) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address dst, uint256 wad) external returns (bool);
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
    event WETHWrapped(uint256 amount);
    event WETHUnwrapped(uint256 amount);
    
    // ============ State Variables ============
    address public constant OPTION_BOOK = 0xd58b814C7Ce700f251722b5555e25aE0fa8169A1; // Base Mainnet OptionBook
    address public constant WETH = 0x4200000000000000000000000000000000000006; // Base WETH
    uint256 public totalDeposited;
    uint256 public lockedInStrategy; // Amount locked in active options positions
    
    // ============ Constructor ============
    constructor() ERC20("Vultara ETH Vault", "vETH") Ownable(msg.sender) {}

    // ============ Core Vault Functions ============

    /**
     * @notice Deposit ETH into the vault
     * @dev Mints vault shares 1:1 with ETH deposited. Funds are pooled for strategy execution.
     */
    function totalAssets() public view returns (uint256) {
        // Return total managed assets: Cash + WETH + Locked
        return address(this).balance + IWETH(WETH).balanceOf(address(this)) + lockedInStrategy;
    }

    /**
     * @notice Deposit ETH into the vault
     * @dev Mints vault shares based on current share price. 
     *      Formula: shares = (amount * totalSupply) / totalAssets
     */
    function deposit() external payable nonReentrant {
        require(msg.value >= 0.001 ether, "Deposit to small");
        
        uint256 assets = msg.value;
        uint256 shares;
        uint256 _totalSupply = totalSupply();
        
        if (_totalSupply == 0) {
            shares = assets; // Initial 1:1
        } else {
            // Calculate share price based on assets BEFORE this deposit
            // Note: address(this).balance already includes msg.value, so we subtract it
            uint256 totalAssetsBefore = totalAssets() - assets;
            shares = (assets * _totalSupply) / totalAssetsBefore;
        }
        
        _mint(msg.sender, shares);
        totalDeposited += assets; // Statistic only
        
        emit DepositReceived(msg.sender, assets, shares);
    }

    /**
     * @notice Withdraw ETH from the vault
     * @dev Burns shares and returns proportional share of the pool (including yield)
     */
    function withdraw(uint256 shares) external nonReentrant {
        require(shares > 0 && balanceOf(msg.sender) >= shares, "Invalid share amount");
        
        // Calculate underlying ETH value of the shares
        // Formula: assets = (shares * totalAssets) / totalSupply
        uint256 ethAmount = (shares * totalAssets()) / totalSupply();
        
        require(address(this).balance >= ethAmount, "Insufficient liquidity (funds deployed)");
        
        _burn(msg.sender, shares);
        
        // Update stats (approximate)
        if (totalDeposited >= ethAmount) {
             totalDeposited -= ethAmount;
        }
        
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "Transfer failed");
        
        emit WithdrawProcessed(msg.sender, ethAmount, shares);
    }

    // ============ Helper Views for Frontend ============
    
    /**
     * @notice Convert shares to underlying ETH assets
     * @dev Use this to show user's real balance (Principal + Yield)
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (totalSupply() == 0) return shares;
        return (shares * totalAssets()) / totalSupply();
    }

    // ============ Strategy Execution (Thetanuts V4 Integration) ============

    /**
     * @notice Wrap ETH to WETH for Thetanuts V4 compatibility
     * @param amount Amount of ETH to wrap
     */
    function wrapETH(uint256 amount) internal {
        require(address(this).balance >= amount, "Insufficient ETH to wrap");
        IWETH(WETH).deposit{value: amount}();
        emit WETHWrapped(amount);
    }

    /**
     * @notice Unwrap WETH back to ETH
     * @param amount Amount of WETH to unwrap
     */
    function unwrapWETH(uint256 amount) internal {
        require(IWETH(WETH).balanceOf(address(this)) >= amount, "Insufficient WETH");
        IWETH(WETH).withdraw(amount);
        emit WETHUnwrapped(amount);
    }

    /**
     * @notice Execute a Thetanuts V4 Strategy by filling an order
     * @dev Only owner/manager can trigger this to prevent malicious draining via bad orders
     * @param order The Thetanuts Order struct
     * @param signature The maker's signature for the order
     * @param ethAmount Amount of ETH to use as collateral (will be wrapped to WETH)
     */
    function executeStrategy(
        Order calldata order, 
        bytes calldata signature,
        uint256 ethAmount
    ) external onlyOwner nonReentrant {
        require(ethAmount > 0, "Amount must be > 0");
        require(address(this).balance >= ethAmount, "Insufficient vault balance");
        
        // Validate order parameters for security
        require(order.collateral == WETH, "Only WETH collateral supported");
        require(order.expiry > block.timestamp, "Order already expired");
        require(order.orderExpiryTimestamp > block.timestamp, "Order signature expired");
        
        // Step 1: Wrap ETH to WETH for Thetanuts V4 compatibility
        wrapETH(ethAmount);
        
        // Step 2: Approve OptionBook to spend WETH
        bool approved = IWETH(WETH).approve(OPTION_BOOK, ethAmount);
        require(approved, "WETH approval failed");
        
        // Step 3: Execute the fillOrder on Thetanuts V4 OptionBook
        IOptionBook(OPTION_BOOK).fillOrder(order, signature, address(this));
        
        // Track locked amount
        lockedInStrategy += ethAmount;
        
        emit StrategyExecuted(ethAmount, OPTION_BOOK);
    }

    /**
     * @notice Unlock funds after option epoch expires
     * @dev Called by owner when options expire worthless or are settled
     * @param amount Amount to unlock and unwrap back to ETH
     */
    function unlockFunds(uint256 amount) external onlyOwner {
        require(amount <= lockedInStrategy, "Amount exceeds locked funds");
        
        uint256 wethBalance = IWETH(WETH).balanceOf(address(this));
        if (wethBalance >= amount) {
            unwrapWETH(amount);
        }
        
        lockedInStrategy -= amount;
    }

    // ============ View Functions ============
    function getUserBalance(address user) external view returns (uint256) {
        return balanceOf(user); // 1:1
    }

    function getTVL() external view returns (uint256) {
        return address(this).balance + IWETH(WETH).balanceOf(address(this));
    }

    function getAvailableLiquidity() external view returns (uint256) {
        return address(this).balance;
    }

    function getLockedAmount() external view returns (uint256) {
        return lockedInStrategy;
    }

    receive() external payable {}
}

