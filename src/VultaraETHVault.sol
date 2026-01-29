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
    
    // Performance Fee Config
    uint256 public performanceFeeBps = 1000; // 10% (Basis Points: 1000/10000)
    address public feeRecipient;

    event PerformanceFeeUpdated(uint256 newFeeBps);
    event FeeRecipientUpdated(address newRecipient);
    event PerformanceFeeTaken(uint256 profit, uint256 fee);

    constructor() ERC20("Vultara ETH Vault", "vETH") Ownable(msg.sender) {
        feeRecipient = msg.sender;
    }

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
        require(msg.value >= 0.001 ether, "Deposit too small");
        
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
    uint256 public activeStrikePrice;
    uint256 public activeExpiry; // Timestamp
    uint256 public lastEpochYield; // Basis points (e.g. 500 = 5%)

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
        
        // Track locked amount and strategy details
        lockedInStrategy += ethAmount;
        activeStrikePrice = order.strikes.length > 0 ? order.strikes[0] : 0;
        activeExpiry = order.expiry;
        
        emit StrategyExecuted(ethAmount, OPTION_BOOK);
    }

    /**
     * @notice Set performance fee (Max 20%)
     */
    function setPerformanceFee(uint256 _bps) external onlyOwner {
        require(_bps <= 2000, "Fee too high (max 20%)");
        performanceFeeBps = _bps;
        emit PerformanceFeeUpdated(_bps);
    }

    /**
     * @notice Set fee recipient address
     */
    function setFeeRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "Invalid address");
        feeRecipient = _recipient;
        emit FeeRecipientUpdated(_recipient);
    }

    /**
     * @notice Settle funds after option epoch expires
     * @dev Called by owner to realize profits/losses and unwrap WETH
     * @param amountReturned Amount of WETH received back from strategy
     */
    function settleStrategy(uint256 amountReturned) external onlyOwner {
        uint256 wethBalance = IWETH(WETH).balanceOf(address(this));
        
        // Ensure we have enough WETH to unwrap (sanity check)
        uint256 amountToUnwrap = amountReturned > wethBalance ? wethBalance : amountReturned;
        
        if (amountToUnwrap > 0) {
            unwrapWETH(amountToUnwrap);
        }
        
    // Calculate Yield (Simplified for Demo: Yield based on return vs principal)
        // If amountReturned > lockedInStrategy, we made profit.
        if (lockedInStrategy > 0) {
            if (amountReturned > lockedInStrategy) {
                uint256 profit = amountReturned - lockedInStrategy;
                
                // Deduct Performance Fee
                if (performanceFeeBps > 0) {
                    uint256 fee = (profit * performanceFeeBps) / 10000;
                    if (fee > 0 && address(this).balance >= fee) {
                         // Transfer fee to recipient
                        (bool success, ) = payable(feeRecipient).call{value: fee}("");
                        if (success) {
                            profit -= fee; // Reduce profit remaining in vault
                            emit PerformanceFeeTaken(profit + fee, fee);
                            
                            // Adjust amountReturned effectively to reflect net profit in system
                             // Note: We already unwrapped EVERYTHING above. 
                             // So address(this).balance has the full amount.
                             // By sending `fee` out, the `totalAssets()` naturally drops by `fee`.
                        }
                    }
                }

                // Yield BPS = (Net Profit * 10000) / Principal
                lastEpochYield = (profit * 10000) / lockedInStrategy;
            } else {
                lastEpochYield = 0; // No profit or loss
            }
        }
        
        // Reset locked amount (Assuming full settlement)
        if (amountReturned >= lockedInStrategy) {
            lockedInStrategy = 0;
        } else {
            lockedInStrategy -= amountReturned;
        }

        // Reset active strategy data
        activeStrikePrice = 0;
        activeExpiry = 0;
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

