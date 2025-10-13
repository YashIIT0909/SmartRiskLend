// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IRiskRegistry {
    function getRiskScore(
        address borrower
    ) external view returns (uint256, uint256);

    function isRiskFlagged(address borrower) external view returns (bool);
}

interface ILendingPool {
    function setPaused(address user, bool value) external;

    function positions(
        address user
    ) external view returns (uint256, uint256, uint256, bool); // collateral, debt, lastUpdate, isPaused

    function getUserPosition(
        address user
    ) external view returns (uint256, uint256, uint256, bool);
}

contract RiskGuardian {
    address public immutable riskRegistry;
    address public immutable lendingPool;
    address public guardian;
    address public governance;

    // Extra collateral requirements by user
    mapping(address => uint256) public extraCollateralBps;
    // "Top-up by" deadlines by user
    mapping(address => uint256) public topUpDeadline;

    event BorrowingPaused(address indexed user);
    event BorrowingUnpaused(address indexed user);
    event ExtraCollateralRequired(address indexed user, uint256 extraBps);
    event TopUpDeadlineSet(address indexed user, uint256 deadline);

    modifier onlyGuardianOrGov() {
        require(
            msg.sender == guardian || msg.sender == governance,
            "Not authorized"
        );
        _;
    }

    constructor(
        address _riskRegistry,
        address _lendingPool,
        address _governance
    ) {
        riskRegistry = _riskRegistry;
        lendingPool = _lendingPool;
        governance = _governance;
        guardian = msg.sender;
    }

    // Pause borrowing for risk-flagged user
    function enforcePause(address user) external onlyGuardianOrGov {
        require(IRiskRegistry(riskRegistry).isRiskFlagged(user), "Not flagged");
        ILendingPool(lendingPool).setPaused(user, true);
        emit BorrowingPaused(user);
    }

    // Unpause borrowing for user (if healthy/risk cleared)
    function unpause(address user) external onlyGuardianOrGov {
        ILendingPool(lendingPool).setPaused(user, false);
        emit BorrowingUnpaused(user);
    }

    // Require extra collateral by % basis points (over standard LTV)
    function requireExtraCollateral(
        address user,
        uint256 bps
    ) external onlyGuardianOrGov {
        require(bps > 0, "Zero bps");
        extraCollateralBps[user] = bps;
        emit ExtraCollateralRequired(user, bps);
    }

    // Set a "top up by" deadline after which user gets paused/liquidated
    function setTopUpDeadline(
        address user,
        uint256 deadline
    ) external onlyGuardianOrGov {
        require(deadline > block.timestamp, "Deadline must be in future");
        topUpDeadline[user] = deadline;
        emit TopUpDeadlineSet(user, deadline);
    }

    // Whether user requires extra collateral (for LendingPool to check)
    function getExtraCollateralBps(
        address user
    ) external view returns (uint256) {
        return extraCollateralBps[user];
    }

    // Whether there is a pending top-up deadline
    function getTopUpDeadline(address user) external view returns (uint256) {
        return topUpDeadline[user];
    }

    // Guardian key rotation (governance only)
    function rotateGuardian(address newGuardian) external {
        require(msg.sender == governance, "Only governance");
        guardian = newGuardian;
    }
}
