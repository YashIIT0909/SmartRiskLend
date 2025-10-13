// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ILendingPoolParam {
    function setLiquidationThreshold(uint256 newThresh) external;

    function setLTV(uint256 newLTV) external;
}

interface IRiskRegistryAdmin {
    function setPauseThreshold(uint256 newThreshold) external;

    function updateSigner(address newSigner) external;
}

interface IRiskGuardian {
    function rotateGuardian(address newGuardian) external;
}

contract Governance {
    address public admin;
    address public lendingPool;
    address public riskRegistry;
    address public riskGuardian;
    bool public protocolPaused;

    event ProtocolPaused(bool paused);
    event LiquidationThresholdUpdated(uint256 newValue);
    event LTVUpdated(uint256 newValue);
    event PauseThresholdUpdated(uint256 newValue);
    event SignerRotated(address newAgentSigner);
    event RiskGuardianUpdated(address newGuardian);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    constructor(
        address _lendingPool,
        address _riskRegistry,
        address _riskGuardian
    ) {
        admin = msg.sender;
        lendingPool = _lendingPool;
        riskRegistry = _riskRegistry;
        riskGuardian = _riskGuardian;
    }

    function setProtocolPaused(bool val) external onlyAdmin {
        protocolPaused = val;
        emit ProtocolPaused(val);
    }

    // Update lending pool parameters
    function updateLiquidationThreshold(uint256 val) external onlyAdmin {
        ILendingPoolParam(lendingPool).setLiquidationThreshold(val);
        emit LiquidationThresholdUpdated(val);
    }

    function updateLTV(uint256 val) external onlyAdmin {
        ILendingPoolParam(lendingPool).setLTV(val);
        emit LTVUpdated(val);
    }

    // Update risk thresholds
    function updateRiskPauseThreshold(uint256 val) external onlyAdmin {
        IRiskRegistryAdmin(riskRegistry).setPauseThreshold(val);
        emit PauseThresholdUpdated(val);
    }

    // Rotate AI agent EIP-712 signing key
    function updateAgentSigner(address newSigner) external onlyAdmin {
        IRiskRegistryAdmin(riskRegistry).updateSigner(newSigner);
        emit SignerRotated(newSigner);
    }

    // Rotate risk guardian
    function updateRiskGuardian(address newGuardian) external onlyAdmin {
        riskGuardian = newGuardian;
        // Call guardian's rotate function, if needed
        IRiskGuardian(riskGuardian).rotateGuardian(newGuardian);
        emit RiskGuardianUpdated(newGuardian);
    }

    // Admin key rotation
    function updateAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }
}
