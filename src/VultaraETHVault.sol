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
    
    event DepositReceived(address indexed user, uint256 ethAmount, uint256 shares);
    event WithdrawProcessed(address indexed user, uint256 ethAmount, uint256 shares);
    event StrategyExecuted(uint256 ethAmount, address indexed optionBook);
    event WETHWrapped(uint256 amount);
    event WETHUnwrapped(uint256 amount);
    event WithdrawalScheduled(address indexed user, uint256 shares);
    
    address public constant OPTION_BOOK = 0xd58b814C7Ce700f251722b5555e25aE0fa8169A1;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    uint256 public totalDeposited;
    uint256 public lockedInStrategy; // Amount locked in active options positions
    
    constructor() ERC20("Vultara ETH Vault", "vETH") Ownable(msg.sender) {}

    /**
     * @notice Deposit ETH into the vault
     * @dev Mints vault shares 1:1 with ETH deposited. Funds are pooled for strategy execution.
     */
    function totalAssets() public view returns (uint256) {
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

    mapping(address => uint256) public pendingWithdrawals;
    uint256 public totalPendingShares;

    /**
     * @notice Schedule a withdrawal for the next window (Friday)
     * @dev Transfers shares to the vault as escrow. These shares still earn yield until claimed.
     */
    function scheduleWithdraw(uint256 shares) external nonReentrant {
        require(shares > 0 && balanceOf(msg.sender) >= shares, "Invalid share amount");
        require(pendingWithdrawals[msg.sender] == 0, "Withdrawal already scheduled. Claim or Cancel first.");
        _transfer(msg.sender, address(this), shares);
        
        pendingWithdrawals[msg.sender] = shares;
        totalPendingShares += shares;
        
        emit WithdrawalScheduled(msg.sender, shares);
    }

    /**
     * @notice Cancel a scheduled withdrawal
     * @dev Returns shares to user
     */
    function cancelWithdraw() external nonReentrant {
        uint256 shares = pendingWithdrawals[msg.sender];
        require(shares > 0, "No pending withdrawal");

        delete pendingWithdrawals[msg.sender];
        totalPendingShares -= shares;

        _transfer(address(this), msg.sender, shares);
    }

    /**
     * @notice Claim pending withdrawal (Call this on Friday after options expiry)
     * @dev Burns escrowed shares and sends ETH. Fails if vault has insufficient liquidity.
     */
    function claimWithdraw() external nonReentrant {
        uint256 shares = pendingWithdrawals[msg.sender];
        require(shares > 0, "No pending withdrawal");
        
        // Calculate ETH value using CURRENT share price (User earned yield while waiting!)
        uint256 ethAmount = (shares * totalAssets()) / totalSupply();
        
        require(address(this).balance >= ethAmount, "Insufficient liquidity. Come back Friday!");
        
        delete pendingWithdrawals[msg.sender];
        totalPendingShares -= shares;
        _burn(address(this), shares);
        
        if (totalDeposited >= ethAmount) {
             totalDeposited -= ethAmount;
        }
        
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "Transfer failed");
        
        emit WithdrawProcessed(msg.sender, ethAmount, shares);
    }
    
    /** 
     * @notice Check how much ETH is 'free' to be deployed in strategy, respecting withdrawal requests.
     * @dev Manager should call this before executeStrategy.
     */
    function getInvestableAmount() public view returns (uint256) {
        uint256 totalEth = address(this).balance;
        
        // Calculate estimated ETH needed for pending withdrawals
        // Note: This is an estimate because share price might change slightly
        uint256 pendingEthNeeded = (totalPendingShares * totalAssets()) / totalSupply();
        
        if (pendingEthNeeded >= totalEth) return 0;
        return totalEth - pendingEthNeeded;
    }

    /**
     * @notice Convert shares to underlying ETH assets
     * @dev Use this to show user's real balance (Principal + Yield)
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (totalSupply() == 0) return shares;
        return (shares * totalAssets()) / totalSupply();
    }

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

