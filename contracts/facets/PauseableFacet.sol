// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/LibDiamond.sol";
import "../utils/functions/AppStorage.sol";

import "../utils/validators/Error.sol";

contract PauseableFacet is AppStorage {
event ProtocolPauseTriggered(address indexed pauser, uint256 timestamp);
event ProtocolUnPauseTriggered(address indexed pauser, uint256 timestamp);

    
    modifier protocolNotPaused() {
        if (_appStorage.isPaused) revert ProtocolPaused();
        _;
    }
    
    modifier protocolPaused() {
        if (!_appStorage.isPaused) revert ProtocolActive();
        _;
    }

    function pauseProtocol() external {
        LibDiamond.enforceIsContractOwner();
        _appStorage.isPaused = true;
        emit ProtocolPauseTriggered(msg.sender, block.timestamp);
    }

    function unpauseProtocol() external {
        LibDiamond.enforceIsContractOwner();
        _appStorage.isPaused = false;
        emit ProtocolUnPauseTriggered(msg.sender, block.timestamp);
    }

    function isProtocolPaused() external view returns (bool) {
        return _appStorage.isPaused;
    }
}