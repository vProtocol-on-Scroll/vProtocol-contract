// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {AppStorage} from "../utils/functions/AppStorage.sol";
import {CoreVault} from "../facets/CoreVault.sol";
import "../utils/validators/Error.sol";
import "../model/Event.sol";
import "../model/Protocol.sol";

contract CorePoolConfigFacet is AppStorage {


     event VaultCreated(address indexed asset, address vault);
    event FeesUpdated(uint256 feeBps);
    event VaultConfigUpdated(address vault, uint256 ltvBps, uint256 liquidationThresholdBps);

    
function createVault(
    IERC20 asset,
    string memory name,
    string memory symbol,
    uint256 ltvBps,
    uint256 liquidationThresholdBps,
    uint256 _initialDeposit
) external payable {
    LibDiamond.enforceIsContractOwner();
    require(address(asset) != address(0), "Invalid asset");
    require(ltvBps <= 10000, "LTV > 100%");
    
       CoreVault vault = new CoreVault(asset, name, symbol);
        vault.initialize{value: msg.value}(_initialDeposit);
        
        // Store vault config
        VaultConfig storage _vaultConfig = _appStorage.s_vaultConfigs[address(vault)];
        _vaultConfig.ltvBps = ltvBps;
        _vaultConfig.liquidationThresholdBps = liquidationThresholdBps;
        _vaultConfig.totalDeposits = 0;
        _vaultConfig.totalBorrowed = 0;
        
        // Add this line to map asset to vault
        _appStorage.assetToVault[address(asset)] = address(vault);
        
        emit VaultCreated(address(asset), address(vault));
    }


    
    function getVaultConfig(address asset) external view returns (VaultConfig memory) {
        address vaultAddress = _appStorage.assetToVault[asset];
        require(vaultAddress != address(0), "Vault not found");
        return _appStorage.s_vaultConfigs[vaultAddress];
    }
    
    function setFeeRecipient(address _newRecipient) external  {
        LibDiamond.enforceIsContractOwner();
        _appStorage.s_protocolFeeRecipient = _newRecipient;
    }
    
    function setFees(uint256 _feeBps) external  {
        LibDiamond.enforceIsContractOwner();
        if (_feeBps > 1000) revert Protocol__FeeTooHight(); // Max 10%
        _appStorage.s_protocolFeeBps = _feeBps;
        emit FeesUpdated(_feeBps);
    }
    
    function updateVaultConfig(
        address vault,
        uint256 ltvBps,
        uint256 liquidationThresholdBps
    ) external {
        LibDiamond.enforceIsContractOwner();
        VaultConfig  storage config = _appStorage.s_vaultConfigs[vault];
        config.ltvBps = ltvBps;
        config.liquidationThresholdBps = liquidationThresholdBps;
        emit VaultConfigUpdated(vault, ltvBps, liquidationThresholdBps);
    }
    
    // ======== GETTERS ======== //
    function getVault(address asset) external view returns (address) {
        return _appStorage.assetToVault[asset];
    }
    
    // function getVaultConfig(address vault) external view returns (VaultConfig memory) {
    //     VaultConfig memory _vaultConfig =  _appStorage.s_vaultConfigs[vault];
    //     return _vaultConfig;
    // }
    
    function getProtocolFeeRecipient () external view returns (address) {
        return _appStorage.s_protocolFeeRecipient;
    }
    
    function getProtocolFeeBps() external view returns (uint256) {
        return _appStorage.s_protocolFeeBps;
    }
}
