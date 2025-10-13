// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IOracleAdapter {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IRiskRegistry {
    function getRiskScore(
        address borrower
    ) external view returns (uint256, uint256);

    function isRiskFlagged(address borrower) external view returns (bool);
}

contract LendingPool {
    struct Position {
        uint256 collateral; // Amount of collateral (in wei)
        uint256 debt; // Amount of borrowed asset (in wei)
        uint256 lastUpdate;
        bool isPaused; // Risk pause flag
    }

    // Addresses
    address public immutable oracle;
    address public immutable riskRegistry;

    // Lending pool parameters
    uint256 public constant LIQUIDATION_THRESHOLD_BPS = 8000; // 80%
    uint256 public constant MIN_HEALTH_FACTOR = 10000; // 1.0 scaled by 10000
    uint256 public constant LTV_BPS = 7500; // Max LTV: 75%

    mapping(address => Position) public positions;

    event DepositCollateral(address indexed user, uint256 amount);
    event WithdrawCollateral(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidation(
        address indexed liquidator,
        address indexed user,
        uint256 repayAmount
    );

    constructor(address _oracle, address _riskRegistry) {
        oracle = _oracle;
        riskRegistry = _riskRegistry;
    }

    // Core collateral deposit
    function depositCollateral() external payable {
        require(msg.value > 0, "Zero collateral");
        positions[msg.sender].collateral += msg.value;
        positions[msg.sender].lastUpdate = block.timestamp;
        emit DepositCollateral(msg.sender, msg.value);
    }

    // Withdraw collateral if healthy
    function withdrawCollateral(uint256 amount) external {
        require(amount > 0, "Zero withdraw");
        Position storage pos = positions[msg.sender];
        require(pos.collateral >= amount, "Not enough collateral");
        pos.collateral -= amount;
        require(_isHealthy(msg.sender), "Would breach health factor");
        pos.lastUpdate = block.timestamp;
        payable(msg.sender).transfer(amount);
        emit WithdrawCollateral(msg.sender, amount);
    }

    // Borrow if health check and risk registry allow
    function borrow(uint256 amount) external {
        require(amount > 0, "Zero borrow");
        Position storage pos = positions[msg.sender];
        require(!pos.isPaused, "Paused: Risk flagged");
        require(
            !_isRiskFlagged(msg.sender),
            "Borrowing restricted by risk agent"
        );

        // Price fetched via OracleAdapter
        uint256 collateralValue = _getCollateralValue(msg.sender);
        uint256 maxBorrow = (collateralValue * LTV_BPS) / 10000;
        require(pos.debt + amount <= maxBorrow, "Exceeds max borrow");

        pos.debt += amount;
        require(_isHealthy(msg.sender), "Unsafe health factor");
        pos.lastUpdate = block.timestamp;
        // Use wrapped ETH or a stablecoin for lending in production
        payable(msg.sender).transfer(amount);

        emit Borrow(msg.sender, amount);
    }

    // Repay loan
    function repay() external payable {
        require(msg.value > 0, "Zero repay");
        Position storage pos = positions[msg.sender];
        require(pos.debt > 0, "No debt");
        uint256 repayAmount = msg.value > pos.debt ? pos.debt : msg.value;
        pos.debt -= repayAmount;
        pos.lastUpdate = block.timestamp;
        emit Repay(msg.sender, repayAmount);
        // Optionally refund excess ETH
        if (msg.value > repayAmount) {
            payable(msg.sender).transfer(msg.value - repayAmount);
        }
    }

    // Anyone liquidates unhealthy positions
    function liquidate(address borrower) external payable {
        require(!_isHealthy(borrower), "Health factor ok");
        Position storage pos = positions[borrower];
        require(pos.debt > 0, "No debt to liquidate");
        uint256 repayAmount = pos.debt > msg.value ? msg.value : pos.debt;
        pos.debt -= repayAmount;

        // Give liquidator discounted collateral (5% bonus)
        uint256 collateralToSeize = (repayAmount * 105) / 100; // 5% bonus
        require(pos.collateral >= collateralToSeize, "Insufficient collateral");
        pos.collateral -= collateralToSeize;
        payable(msg.sender).transfer(collateralToSeize);

        pos.lastUpdate = block.timestamp;
        emit Liquidation(msg.sender, borrower, repayAmount);
    }

    // -------- Internal utils --------

    function _getCollateralValue(address user) internal view returns (uint256) {
        uint256 price = IOracleAdapter(oracle).getAssetPrice(address(0)); // ETH collateral
        return (positions[user].collateral * price) / 1e18;
    }

    function _getHealthFactor(address user) public view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.debt == 0) return type(uint256).max;
        uint256 collateralValue = _getCollateralValue(user);
        // Health = (collateral * threshold) / debt
        return (collateralValue * LIQUIDATION_THRESHOLD_BPS) / (pos.debt * 1e4);
    }

    function _isHealthy(address user) internal view returns (bool) {
        return _getHealthFactor(user) >= MIN_HEALTH_FACTOR;
    }

    function _isRiskFlagged(address user) internal view returns (bool) {
        return IRiskRegistry(riskRegistry).isRiskFlagged(user);
    }

    // Admin function to set risk status (for demo/testing, in production only Guardian should call)
    function setPaused(address user, bool value) external {
        positions[user].isPaused = value;
    }

    // View functions
    function getUserPosition(
        address user
    )
        external
        view
        returns (uint256 collat, uint256 debt, uint256 health, bool paused)
    {
        collat = positions[user].collateral;
        debt = positions[user].debt;
        health = _getHealthFactor(user);
        paused = positions[user].isPaused;
    }
}
