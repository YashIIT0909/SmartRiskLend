// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract RiskRegistry {
    struct RiskRecord {
        uint256 score; // Risk score: e.g., 0 (safe) – 10000 (maximum risk, 4 decimals)
        uint256 expiresAt; // When this assessment expires
        bytes32 metadataHash; // Optional: hash of justification or explainability blob
        uint256 updatedAt; // Last update time
    }

    mapping(address => RiskRecord) public riskOf;
    address public authorizedSigner; // AI agent’s EOA or contract
    uint256 public pauseThreshold = 8000; // Risk score above which borrower is paused (default: 0.8 = 8000)
    uint256 public extraCollateralThreshold = 6000; // Score above which extra collateral required (optional)
    address public admin;
    event RiskScoreUpdated(
        address indexed borrower,
        uint256 score,
        uint256 expiresAt,
        bytes32 metadataHash
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    constructor(address _signer) {
        authorizedSigner = _signer;
        admin = msg.sender;
    }

    // Set risk score via authorized AI off-chain signature (EIP-712)
    function setRiskScore(
        address borrower,
        uint256 score,
        uint256 expiresAt,
        bytes32 metadataHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(borrower != address(0), "Zero borrower");
        require(score <= 10000, "Score too high");
        // Compose message and validate signature
        bytes32 message = keccak256(
            abi.encodePacked(
                borrower,
                score,
                expiresAt,
                metadataHash,
                address(this)
            )
        );
        address signer = ecrecover(
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
            ),
            v,
            r,
            s
        );
        require(signer == authorizedSigner, "Bad signature");

        // Update registry
        riskOf[borrower] = RiskRecord(
            score,
            expiresAt,
            metadataHash,
            block.timestamp
        );
        emit RiskScoreUpdated(borrower, score, expiresAt, metadataHash);
    }

    // Anyone can read current risk score and expiry
    function getRiskScore(
        address borrower
    ) external view returns (uint256 score, uint256 expiresAt) {
        RiskRecord storage rec = riskOf[borrower];
        return (rec.score, rec.expiresAt);
    }

    // Returns true if flagged for pause by score
    function isRiskFlagged(address borrower) external view returns (bool) {
        RiskRecord storage rec = riskOf[borrower];
        if (block.timestamp > rec.expiresAt) return false; // Risk expired
        return rec.score >= pauseThreshold;
    }

    // Admin management functions
    function setPauseThreshold(uint256 newThreshold) external onlyAdmin {
        require(newThreshold <= 10000, "Too high");
        pauseThreshold = newThreshold;
    }

    function setExtraCollateralThreshold(
        uint256 newThreshold
    ) external onlyAdmin {
        require(newThreshold <= 10000, "Too high");
        extraCollateralThreshold = newThreshold;
    }

    function updateSigner(address newSigner) external onlyAdmin {
        authorizedSigner = newSigner;
    }

    function updateAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }
}
